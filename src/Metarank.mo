import Result "mo:base/Result";
import ExtCore "mo:ext/Core";

module {

    // The following type describes the required public functionality for this canister
    public type MetarankInterface = actor {

        // NOTE: there are important requirements of the http_request method
        // however, I'm not sure how to document them here. See main.mo

        // EXT standard token balance request
        balance : shared query (request : ExtCore.BalanceRequest) -> async ExtCore.BalanceResponse;

        // EXT standard token bearer request
        bearer : shared query (token : ExtCore.TokenIdentifier) -> async Result.Result<ExtCore.AccountIdentifier, ExtCore.CommonError>;

        // EXT standard transfer request. We should throw an error here.
        transfer : shared (request : ExtCore.TransferRequest) -> async ExtCore.TransferResponse;

        // Ext standard to retrieve token metadata
        // metadata : (token : ExtCore.TokenIdentifier) -> async Result.Result<ExtMetadata, ExtCore.CommonError>;

        // Ext standard to retrieve token supply. Should always be one.
        // supply : (token : ExtCore.TokenIdentifier) -> async Result.Result<ExtCore.Balance, ExtCore.CommonError>;

        // --

        // TODO: add methods for plug integration

        // --

        // TODO: add method to mint badges for all players
        // 1. get all players from Metascore
        // 2. get all ranks or data required to generate ranks
        // 3. mint badges

        // TODO: add method to query rank for an identity (i.e. supported wallet principal)

    };

    // Including this here because it isn't available anywhere else at the moment.
    public type ExtMetadata = {
        #fungible : {
            name : Text;
            symbol : Text;
            decimals : Nat8;
            metadata : ?[Blob];
        };
        #nonfungible : {
            metadata : ?[Blob];
        };
    };

};