import Array "mo:base/Array";
import Text "mo:base/Text";
import Char "mo:base/Char";
import Assets "mo:assets/AssetStorage";
import Blob "mo:base/Blob";

import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Time "mo:base/Time";

import AID "mo:ext/util/AccountIdentifier";
import ExtCore "mo:ext/Core";
import ExtNonFungible "mo:ext/NonFungible";
import ExtCommon "mo:ext/Common";
import DLHttp "mo:dl-nft/http";


import Interface "Metarank";


// The compiler will complain about this whole actor until it implements MetarankInterface
// TODO: implement MetarankInterface
shared ({ caller = owner }) actor class MetaRank() : async Interface.MetarankInterface = canister {

    // TODO: Create internal asset state (asset index, asset payload, etc.)
    // TODO: Create internal ledger state (token id, player, rank record)
    // TODO: Create Rank type (assetIndex, title, etc)


    ////////////
    // Types //
    //////////
    type Time = Time.Time;
    type AccountIdentifier = ExtCore.AccountIdentifier;
    type SubAccount = ExtCore.SubAccount;
    type User = ExtCore.User;
    type Balance = ExtCore.Balance;
    type TokenIdentifier = ExtCore.TokenIdentifier;
    type TokenIndex  = ExtCore.TokenIndex;
    type Extension = ExtCore.Extension;
    type CommonError = ExtCore.CommonError;
    type BalanceRequest = ExtCore.BalanceRequest;
    type BalanceResponse = ExtCore.BalanceResponse;
    type TransferRequest = ExtCore.TransferRequest;
    type TransferResponse = ExtCore.TransferResponse;
    type MintRequest  = ExtNonFungible.MintRequest;
    type Metadata = ExtCommon.Metadata;

    type HttpRequest = DLHttp.Request;
    type HttpResponse = DLHttp.Response;

    type AssetIndex = ExtCore.TokenIndex;


    public type Asset = {
        contentType : Text;
        payload     : [Blob];
    };

    type Token = {
        createdAt   : Int;
        owner : AccountIdentifier;
        assetIndex : AssetIndex;
    }; 

    ////////////
    // State //
    //////////


    stable var nextTokenId : TokenIndex = 0;
    stable var assetIndex : AssetIndex = 0;

    stable var stableAssetLedger : [(AssetIndex, Asset)] = [];
    stable var stableTokenLedger : [(TokenIndex, Token)] = [];
    
    var tokenledger : HashMap.HashMap<TokenIndex, Token> = HashMap.fromIter(stableTokenLedger.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
    var assetledger : HashMap.HashMap<AssetIndex, Asset> = HashMap.fromIter(stableAssetLedger.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);

    system func preupgrade() {
        stableAssetLedger := Iter.toArray(assetledger.entries());
        stableTokenLedger := Iter.toArray(tokenledger.entries());
    };

    system func postupgrade() {
        stableAssetLedger := [];
        stableTokenLedger := [];
    };

    let tokensOfUser = HashMap.HashMap<ExtCore.AccountIdentifier, [ExtCore.TokenIndex]>(
            0,
            AID.equal,
            AID.hash,
        );


    ////////////////
    /// Admin /////
    ///////////////

    // List of Metascore admins, these are principals that perform admin actions.
    private stable var admins = [owner];

    // Use this to add an admin-only restriction
    // ex: assert(_isAdmin(caller));
    private func _isAdmin(p : Principal) : Bool {
        for (a in admins.vals()) {
            if (a == p) { return true; };
        };
        false;
    };

    // Adds a new principal as an admin.
    // @auth: owner
    public shared({caller}) func addAdmin(p : Principal) : async () {
        assert(caller == owner);
        admins := Array.append(admins, [p]);
    };

    // Removes the given principal from the list of admins.
    // @auth: owner
    public shared({caller}) func removeAdmin(p : Principal) : async () {
        assert(caller == owner);
        admins := Array.filter(
            admins,
            func (a : Principal) : Bool {
                a != p;
            },
        );
    };

    // Check whether the given principal is an admin.
    // @auth: admin
    public query({caller}) func isAdmin(p : Principal) : async Bool {
        assert(_isAdmin(caller));
        for (a in admins.vals()) {
            if (a == p) return true;
        };
        return false;
    };






    /////////////
    // Things //
    ///////////

    // Ext core

    let EXTENSIONS : [Extension] = ["@ext/nonfungible"];

    public shared query func extensions () : async [Extension] {
        EXTENSIONS;
    };

    public shared query func balance (request : ExtCore.BalanceRequest) : async ExtCore.BalanceResponse {
        if (not ExtCore.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(canister))) {
            return #err(#InvalidToken(request.token));
        };
        let tokenIndex = ExtCore.TokenIdentifier.getIndex(request.token);
        let aid = ExtCore.User.toAID(request.user);
        switch (tokenledger.get(tokenIndex)) {
            case (?token) {
                if (AID.equal(aid, token.owner)) return #ok(1);
                return #ok(0);
            };
            case Null #err(#InvalidToken(request.token));
        };
    };

    // The NFT Badges are non-transferrable. Any transfer request will be denied. 
    public shared({ caller }) func transfer (request : TransferRequest) : async TransferResponse {
        if (request.amount != 1) {
            return #err(#Other("Only logical transfer amount for an NFT is 1, got" # Nat.toText(request.amount) # "."));
        };
        if (not ExtCore.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(canister))) {
            return #err(#InvalidToken(request.token));
        };
        return #err(#Rejected);
    };



    // Ext nonfungible

    public shared query func bearer (token : TokenIdentifier) : async Result.Result<AccountIdentifier, CommonError> {
        if (not ExtCore.TokenIdentifier.isPrincipal(token, Principal.fromActor(canister))) {
            return #err(#InvalidToken(token));
        };
        let tokenIndex = ExtCore.TokenIdentifier.getIndex(token);
        switch (tokenledger.get(tokenIndex)) {
            case (?token) #ok(token.owner);
            case Null #err(#InvalidToken(token));
        };
    };

    public shared({ caller }) func mintNFT (request : MintRequest) : async () {
        let recipient = ExtCore.User.toAID(request.to);
        let tokenIndex = nextTokenId;
        let token = { createdAt = Time.now();
                      assetIndex = 0:Nat32;
                      owner = recipient; 
                    }; 
        tokenledger.put(tokenIndex, token);
        _indexToken(tokenIndex, recipient, tokensOfUser);
        nextTokenId := nextTokenId + 1;
    };



    // Just useful things

    public query func readLedger () : async [(TokenIndex, Token)] {
        Iter.toArray(tokenledger.entries());
    };


    


    // Convenience method to add a token to our denormalized index maps
    private func _indexToken (
        token : ExtCore.TokenIndex,
        id : ExtCore.AccountIdentifier,
        map : HashMap.HashMap<ExtCore.AccountIdentifier, [ExtCore.TokenIndex]>
    ) : () {
        switch (map.get(id)) {
            case (null) map.put(id, [token]);
            case (?tokens) map.put(id, Array.append(tokens, [token]));
        };
    };



    ////////////////////
    ////// DAB Js /////
    //////////////////

    /*  Interaface expected by DAB Js
        balance: IDL.Func([BalanceRequest], [BalanceResult], ['query']),
        details: IDL.Func([TokenIdentifier], [DetailsResult], ['query']),
        tokens: IDL.Func([AccountIdentifier], [TokensResult], ['query']),
        tokens_ext: IDL.Func([AccountIdentifier], [TokenExtResult], []),
        transfer: IDL.Func([TransferRequest], [TransferResult], []),
        metadata: IDL.Func([TokenIdentifier], [MetadataResult], ['query']),
    */

    type Listing = {
        locked : ?Time;
        seller : Principal;
        price : Nat64;
    };

    type DetailsResult = {
        #ok : (AccountIdentifier, ?Listing);
        #err : CommonError;
    };

    // public query func details () : async DetailsResult {

    // };

    public query func tokens (accountIdentifier : AccountIdentifier) : async Result.Result<[TokenIndex], CommonError> {
        switch(tokensOfUser.get(accountIdentifier)) {
            case (?tokenIndexList) return #ok(tokenIndexList);
            case Null #err(#Other("The user doesn't have any tokens in this collection")); 
        };
    };

    // Returns all tokens of a user. 
    // Used by DAB Js
    type tokenExt = (TokenIndex, ?[Listing], ?[Nat8]);
    public func tokens_ext (accountIdentifier : AccountIdentifier) : async Result.Result<[tokenExt], CommonError> {
        switch(tokensOfUser.get(accountIdentifier)) {
            case (?tokenIndexList) {
                let tokenExtList = Array.map(tokenIndexList, 
                                                func(tokenIndex : TokenIndex) : tokenExt { (tokenIndex, null, null); } 
                                            );   

                return #ok(tokenExtList);
            };
            case Null #err(#Other("The user doesn't have any tokens in this collection")); 
        };
    };

    // public query func metadata (tokenIdentifier : TokenIdentifier) : async Result.Result<Metadata, CommonError> {

    // };



    ///////////////////////
    ////// HTTP /////////
    /////////////////////




    // Given a URL of a token, returns the badge image. 
    // Plug, Stoic uses this to request a preview of a certain token ID
    // A url is of the form https://<canister id>.ic0.app/?type=thumbnail&tokenid=<tokenIdentifier>

    public query func http_request(request : HttpRequest) : async HttpResponse {
        Debug.print("Handle HTTP Url: " # request.url);
            
        if (Text.contains(request.url, #text("tokenid"))) {
            // EXT preview
            let path = Iter.toArray(Text.tokens(request.url, #text("tokenid=")));
            let tokenIdentifier = path[1];
            Debug.print("Handle HTTP Token Identifier: " # tokenIdentifier);            
            return httpBadgeFromTokenIdentifier(path[1]);
        };

        let path = Iter.toArray(Text.tokens(request.url, #text("/")));
        if (path[0] == "Token") {
            Debug.print("Handle HTTP Token Index: " # path[1]);
            switch ( textToInt(path[1]) ) {
                case (?tokenIndex) return httpBadgeFromTokenIndex(tokenIndex);
                case Null return httpErrorResponse();
            }
        }; 
        return httpErrorResponse();
    };


    private func textToInt(text : Text) : ?Nat32 {
        var result : TokenIndex = 0;
        for (char in Text.toIter(text)) {
            if (Char.isDigit(char)) {
                result := result * 10;
                result += Char.toNat32(char) - Char.toNat32('0');
            }
            else
                return null;
        };
        return ?result;
    };


    private func httpErrorResponse () : HttpResponse {
        return    {
                body = Blob.fromArray([]);
                headers = [];
                status_code = 404;
                streaming_strategy = null;
            };
    };

    private func httpBadgeFromTokenIdentifier(tokenIdentifier : Text) : HttpResponse {

        if (not ExtCore.TokenIdentifier.isPrincipal(tokenIdentifier, Principal.fromActor(canister))) {
            return httpErrorResponse();
            // return #err(#InvalidToken(token));
        };

        let tokenIndex = ExtCore.TokenIdentifier.getIndex(tokenIdentifier);
        return httpBadgeFromTokenIndex(tokenIndex);
    };

    private func httpBadgeFromTokenIndex(tokenIndex : TokenIndex) : HttpResponse {
        
        let cache = "86400";  // Cache one day

        switch(tokenledger.get(tokenIndex)) {
            case (?token) {
                let assetIndex = token.assetIndex;
                switch(assetledger.get(assetIndex)) {
                    case (?asset) {
                        return {
                            body = asset.payload[0];
                            headers = [
                                ("Content-Type", asset.contentType),
                                ("Cache-Control", "max-age=" # cache),
                            ];
                            status_code = 200;
                            streaming_strategy = null;
                        };
                    };
                    case Null httpErrorResponse();
                };
            };
            case Null  httpErrorResponse();
        };
    };
};