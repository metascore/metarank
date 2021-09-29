import ExtCore "mo:ext/Core";
import ExtCommon "mo:ext/Common";
import ExtNonFungible "mo:ext/NonFungible";
import Result "mo:base/Result";

module {
    // Describes the required public functionality for this canister.
    public type MetarankInterface = actor {

        // @ext:core
        // Returns the balance of a requested User.
        balance : query (request : ExtCore.BalanceRequest) -> async ExtCore.BalanceResponse;
        // Returns an array of extensions that the canister supports.
        extensions : query () -> async [ExtCore.Extension];
        // Transfers an given amount of tokens between two users, from and to, with an optional memo.
        transfer : shared (request : ExtCore.TransferRequest) -> async ExtCore.TransferResponse;

        // @ext:common
        metadata   : query (token : ExtCore.TokenIdentifier) -> async ExtCommon.MetadataResponse;
        supply     : query (token : ExtCore.TokenIdentifier) -> async ExtCommon.SupplyResponse;

        // @ext:nonfungible
        bearer  : query (token : ExtCore.TokenIdentifier) -> async ExtNonFungible.BearerResponse;
        mintNFT : shared (request : ExtNonFungible.MintRequest) -> async ();
    };
};