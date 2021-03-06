-module(ecoin_block).

-export([new/7,
         genesis/0,
         genesis/1,
         encode/1,
         decode/1,
         build_merkle_root/1,
         hash/1,
         pp/1]).

-include("ecoin.hrl").

%% @doc Construct a new block
-spec new(uinteger(), uinteger(), hash(), timestamp(), uinteger(), uinteger(),
          [#tx{}]) -> #block{}.
new(BlockNr, Version, PrevBlock, Timestamp, Bits, Nounce, Txns) ->
    Block = #block{nr          = BlockNr,
                   version     = Version,
                   prev_block  = PrevBlock,
                   timestamp   = Timestamp,
                   bits        = Bits,
                   nounce      = Nounce,
                   txns        = array:from_list(Txns)},
    set_merkle_root(Block).

%% @doc Compute and set the merkle root for a block
-spec set_merkle_root(#block{}) -> #block{}.
set_merkle_root(Block = #block{txns = Txns}) ->
    TxHashes = lists:map(fun (T) -> T#tx.hash end, array:to_list(Txns)),
    Block#block{merkle_root = build_merkle_root(TxHashes)}.

%% @doc Construct the genesis block in the current network
-spec genesis() -> #block{}.
genesis() ->
    genesis(ecoin_config:network()).

%% @doc Construct the genesis block in the given network
-spec genesis(network()) -> #block{}.
genesis(main) ->
    BlockNr   = 1,
    Version   = 1,
    PrevBlock = <<0:32/unit:8>>,
    Timestamp = {1231, 6505, 0},
    Bits      = 16#1D00FFFF,
    Nounce    = 2083236893,
    Txns      = [ecoin_tx:genesis()],
    new(BlockNr, Version, PrevBlock, Timestamp, Bits, Nounce, Txns);
genesis(testnet3) ->
    Genesis = genesis(main),
    Genesis1 = Genesis#block{timestamp = {1296, 688602, 0},
                             nounce    = 414098458},
    set_merkle_root(Genesis1).

%% @doc Hash the block header to determine the block hash
-spec hash(#block{}) -> hash().
hash(Block) ->
    ecoin_crypto:hash256(encode(Block#block{txns = undefined})).

%% @doc Encode a block message
-spec encode(#block{}) -> iodata().
encode(#block{
          version     = Version,
          prev_block  = PrevBlock,
          merkle_root = MerkleRoot,
          timestamp   = Timestamp,
          bits        = Bits,
          nounce      = Nounce,
          txns        = Txns
         }) ->
     <<Version:32/little,
       PrevBlock:32/binary,
       MerkleRoot:32/binary,
       (ecoin_util:ts_to_int(Timestamp)):32/little,
       Bits:32/little,
       Nounce:32/little,
       (ecoin_protocol:encode_array(Txns, fun ecoin_tx:encode/1))/binary>>.

%% @doc Decode a block message
-spec decode(binary()) -> {#block{}, binary()} | #block{}.
decode(<<Version:32/little,
         PrevBlock:32/binary,
         MerkleRoot:32/binary,
         Timestamp0:32/little,
         Bits:32/little,
         Nounce:32/little, Binary/binary>>) ->
    Tx = fun ecoin_tx:decode/1,
    Txns = ecoin_protocol:decode_array(Binary, Tx),
    Block = #block{version     = Version,
                   prev_block  = PrevBlock,
                   merkle_root = MerkleRoot,
                   timestamp   = ecoin_util:int_to_ts(Timestamp0),
                   bits        = Bits,
                   nounce      = Nounce},
    case ecoin_protocol:decode_array(Binary, Tx) of
        {Txns, Rest} -> decode(Rest);
        Txns         -> Block#block{txns = Txns}
    end.

%% @doc Pretty print a block
-spec pp(#block{}) -> binary().
pp(Block) ->
    #block{
        version     = Version,
        prev_block  = PrevBlock,
        merkle_root = MerkleRoot,
        timestamp   = Timestamp,
        bits        = Bits,
        nounce      = Nounce,
        txns        = Txns
    } = Block,
    <<"BLOCK:\n"
      "Version:        ", (integer_to_binary(Version))/binary, "\n",
      "Previous block: ", (ecoin_util:bin_to_hexstr(PrevBlock))/binary, "\n",
      "Merkle root:    ", (ecoin_util:bin_to_hexstr(MerkleRoot))/binary, "\n",
      "Timestamp:      ", (ecoin_util:timestamp_to_binary(Timestamp))/binary, "\n",
      "Bits:           ", (integer_to_binary(Bits))/binary, "\n",
      "Nounce:         ", (integer_to_binary(Nounce))/binary, "\n",
      (lists:map(fun tx:pp/1, array:to_list(Txns)))/binary>>.

%% @doc Given the number of transactions, calculate the height of the tree.
-spec calc_tree_height(integer()) -> integer().
calc_tree_height(NumTxns) ->
    round(math:log(NumTxns)/math:log(2)).

-spec calc_tree_width(integer(), integer()) -> integer().
calc_tree_width(NumTxns, Height) ->
    (NumTxns + (1 bsl Height) - 1) bsr Height.

-spec build_merkle_root([hash()]) -> hash().
build_merkle_root(Hashes) ->
    Height = calc_tree_height(length(Hashes)),
    calc_hash(Height, 0, Hashes).

-spec calc_hash(pos_integer(), uinteger(), [hash()]) -> hash().
calc_hash(0, Pos, Hashes) ->
    lists:nth(Pos + 1, Hashes);
calc_hash(Height, Pos, Hashes) ->
    Left = calc_hash(Height - 1, Pos * 2, Hashes),
    Right = case Pos * 2 + 1 < calc_tree_width(length(Hashes), Height - 1) of
                true ->
                    calc_hash(Height - 1, Pos * 2 + 1, Hashes);
                false ->
                    Left
            end,
    ecoin_crypto:hash256([Left, Right]).
