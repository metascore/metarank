import AccountIdentifier "mo:principal/AccountIdentifier";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Bool "mo:base/Bool";
import Char "mo:base/Char";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";
import Text "mo:base/Text";

import ExtCore "mo:ext/Core";
import ExtNonFungible "mo:ext/NonFungible";
import ExtCommon "mo:ext/Common";

import Interface "Metarank";


// The compiler will complain about this whole actor until it implements MetarankInterface
// TODO: implement MetarankInterface
shared ({ caller = owner }) actor class MetaRank() : async Interface.MetarankInterface = this {

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | Asset State                                                           |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    public type Asset = {
        contentType : Text;
        payload     : [Blob];
    };

    private stable var stableAssetLedger : [(ExtCore.TokenIndex, Asset)] = [];
    private var assetLedger = HashMap.fromIter<ExtCore.TokenIndex, Asset>(
        stableAssetLedger.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash,
    );

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | Token State                                                           |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    let BEST_BADGE_INDEX         : ExtCore.TokenIndex = 5; // Top 1
    let SECOND_BEST_BADGE_INDEX  : ExtCore.TokenIndex = 4; // Top 2
    let THIRD_BEST_BADGE_INDEX   : ExtCore.TokenIndex = 3; // Top 3
    let ELITE_GAMER_BADGE_INDEX  : ExtCore.TokenIndex = 2; // Awarded to gamers who score above 85 percentile
    let STRONG_GAMER_BADGE_INDEX : ExtCore.TokenIndex = 1; // Awarded to gamers who score above 50-85 percentile
    let GAMER_BADGE_INDEX        : ExtCore.TokenIndex = 0; // Awarded to gamers who score 0-50 percentile

    type Token = {
        createdAt  : Int;
        owner      : AccountIdentifier.AccountIdentifier;
        assetIndex : ExtCore.TokenIndex;
        rankRecord : RankRecord;
    };

    type RankRecord = {
        rank : Text;
        title : Text;
        totalMetaScore : Nat;
        percentile : Float;
        numericRank : Nat;
    };

    stable var nextTokenId : ExtCore.TokenIndex = 0;
    private stable var stableTokenLedger : [(ExtCore.TokenIndex, Token)] = [];
    private var tokenLedger = HashMap.fromIter<ExtCore.TokenIndex, Token>(
        stableTokenLedger.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash,
    );

    private let tokensOfUser = HashMap.HashMap<
        AccountIdentifier.AccountIdentifier, 
        [ExtCore.TokenIndex]
    >(0, AccountIdentifier.equal, AccountIdentifier.hash);
    for ((tokenId, token) in tokenLedger.entries()) {
        let tokens = switch (tokensOfUser.get(token.owner)) {
            case (null) { []; };
            case (? tk) { tk; };
        };
        tokensOfUser.put(token.owner, Array.append(tokens, [tokenId]));
    };

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | Upgrades                                                              |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    system func preupgrade() {
        stableAssetLedger := Iter.toArray(assetLedger.entries());
        stableTokenLedger := Iter.toArray(tokenLedger.entries());
    };

    system func postupgrade() {
        stableAssetLedger := [];
        stableTokenLedger := [];
    };

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | Admin zone. 🚫                                                        |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

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

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | @ext:core                                                             |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    public shared query func balance (request : ExtCore.BalanceRequest) : async ExtCore.BalanceResponse {
        if (not Principal.equal(request.token.canisterId, Principal.fromActor(this))) {
            return #err(#InvalidToken(request.token));
        };

        let accountId  = ExtCore.User.toAccountIdentifier(request.user);
        switch (tokenLedger.get(request.token.index)) {
            case (null) {
                #err(#InvalidToken(request.token));
            };
            case (? token) {
                if (AccountIdentifier.equal(accountId, token.owner)) return #ok(1);
                #ok(0);
            };
        };
    };

    public query func extensions() : async [ExtCore.Extension] {
        ["@ext/common", "@ext/nonfungible"];
    };

    public shared({ caller }) func transfer (
        request : ExtCore.TransferRequest,
    ) : async ExtCore.TransferResponse {
        #err(#Rejected);
    };

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | @ext:common                                                           |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    public query func metadata(
        tokenId : ExtCore.TokenIdentifier,
    ) : async ExtCommon.MetadataResponse {
        if (not Principal.equal(tokenId.canisterId, Principal.fromActor(this))) {
            return #err(#InvalidToken(tokenId));
        };

        #ok(#nonfungible({metadata = null}));
    };

    public query func supply(
        tokenId : ExtCore.TokenIdentifier,
    ) : async ExtCommon.SupplyResponse {
        if (not Principal.equal(tokenId.canisterId, Principal.fromActor(this))) {
            return #err(#InvalidToken(tokenId));
        };

        switch (tokenLedger.get(tokenId.index)) {
            case (null) { #ok(0); };
            case (? _)  { #ok(1); };
        };
    };

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | @ext:nonfungible                                                      |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    public query func bearer(
        tokenId : ExtCore.TokenIdentifier,
    ) : async ExtNonFungible.BearerResponse {
        if (not Principal.equal(tokenId.canisterId, Principal.fromActor(this))) {
            return #err(#InvalidToken(tokenId));
        };

        switch (tokenLedger.get(tokenId.index)) {
            case (? token) { #ok(token.owner); };
            case (null)    { #err(#InvalidToken(tokenId)); };
        };
    };

    public shared func mintNFT (
        request : ExtNonFungible.MintRequest,
    ) : async () {
        assert(false);
    };

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | 🎨 Assets                                                             |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    public shared({caller}) func uploadAsset(
        index : ExtCore.TokenIndex,
        asset : Asset,
    ) : async () {
        assert(_isAdmin(caller));
        assetLedger.put(index, asset);
    };
};
