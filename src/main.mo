import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Bool "mo:base/Bool";
import Char "mo:base/Char";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";
import Text "mo:base/Text";

import Ext "mo:ext/Ext";
import Interface "mo:ext/Interface";


// The compiler will complain about this whole actor until it implements MetarankInterface
// TODO: implement MetarankInterface
shared ({ caller = owner }) actor class MetaRank() : async Interface.NonFungibleToken = this {

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | Asset State                                                           |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    public type Asset = {
        contentType : Text;
        payload     : [Blob];
    };

    private stable var stableAssetLedger : [(Ext.TokenIndex, Asset)] = [];
    private var assetLedger = HashMap.fromIter<Ext.TokenIndex, Asset>(
        stableAssetLedger.vals(), 0, Ext.TokenIndex.equal, Ext.TokenIndex.hash,
    );

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | Token State                                                           |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    let BEST_BADGE_INDEX         : Ext.TokenIndex = 5; // Top 1
    let SECOND_BEST_BADGE_INDEX  : Ext.TokenIndex = 4; // Top 2
    let THIRD_BEST_BADGE_INDEX   : Ext.TokenIndex = 3; // Top 3
    let ELITE_GAMER_BADGE_INDEX  : Ext.TokenIndex = 2; // Awarded to gamers who score above 85 percentile
    let STRONG_GAMER_BADGE_INDEX : Ext.TokenIndex = 1; // Awarded to gamers who score above 50-85 percentile
    let GAMER_BADGE_INDEX        : Ext.TokenIndex = 0; // Awarded to gamers who score 0-50 percentile

    type Token = {
        createdAt  : Int;
        owner      : Ext.AccountIdentifier;
        assetIndex : Ext.TokenIndex;
        rankRecord : RankRecord;
    };

    type RankRecord = {
        rank : Text;
        title : Text;
        totalMetaScore : Nat;
        percentile : Float;
        numericRank : Nat;
    };

    stable var nextTokenId : Ext.TokenIndex = 0;
    private stable var stableTokenLedger : [(Ext.TokenIndex, Token)] = [];
    private var tokenLedger = HashMap.fromIter<Ext.TokenIndex, Token>(
        stableTokenLedger.vals(), 0, Ext.TokenIndex.equal, Ext.TokenIndex.hash,
    );

    private let tokensOfUser = HashMap.HashMap<
        Ext.AccountIdentifier, 
        [Ext.TokenIndex]
    >(0, Ext.AccountIdentifier.equal, Ext.AccountIdentifier.hash);
    for ((tokenId, token) in tokenLedger.entries()) {
        let tokens = switch (tokensOfUser.get(token.owner)) {
            case (null) { []; };
            case (? tk) { tk; };
        };
        tokensOfUser.put(token.owner, Array.append(tokens, [tokenId]));
    };

    // Checks whether the given token is valid.
    private func checkToken(tokenId : Ext.TokenIdentifier) : ?Ext.TokenIndex {
        switch (Ext.TokenIdentifier.decode(tokenId)) {
            case (#err(e)) { null; };
            case (#ok(canisterId, index)) {
                if (not Principal.equal(canisterId, Principal.fromActor(this))) return null;
                ?index;
            };
        };
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

    public shared query func balance(
        request : Ext.Core.BalanceRequest,
    ) : async Ext.Core.BalanceResponse {
        let index = switch (checkToken(request.token)) {
            case (null) { return #err(#InvalidToken(request.token)); };
            case (? i)  { i; };
        };

        let accountId = Ext.User.toAccountIdentifier(request.user);
        switch (tokenLedger.get(index)) {
            case (null) { #err(#InvalidToken(request.token)); };
            case (? token) {
                if (Ext.AccountIdentifier.equal(accountId, token.owner)) return #ok(1);
                #ok(0);
            };
        };
    };

    public query func extensions() : async [Ext.Extension] {
        ["@ext/common", "@ext/nonfungible"];
    };

    public shared({ caller }) func transfer(
        request : Ext.Core.TransferRequest,
    ) : async Ext.Core.TransferResponse {
        #err(#Rejected);
    };

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | @ext:common                                                           |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    public query func metadata(
        tokenId : Ext.TokenIdentifier,
    ) : async Ext.Common.MetadataResponse {
        switch (checkToken(tokenId)) {
            case (null) { return #err(#InvalidToken(tokenId)); };
            case (? _)  {};
        };

        #ok(#nonfungible({metadata = null}));
    };

    public query func supply(
        tokenId : Ext.TokenIdentifier,
    ) : async Ext.Common.SupplyResponse {
        let index = switch (checkToken(tokenId)) {
            case (null) { return #err(#InvalidToken(tokenId)); };
            case (? i)  { i; };
        };

        switch (tokenLedger.get(index)) {
            case (null) { #ok(0); };
            case (? _)  { #ok(1); };
        };
    };

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | @ext:nonfungible                                                      |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    public query func bearer(
        tokenId : Ext.TokenIdentifier,
    ) : async Ext.NonFungible.BearerResponse {
        let index = switch (checkToken(tokenId)) {
            case (null) { return #err(#InvalidToken(tokenId)); };
            case (? i)  { i; };
        };

        switch (tokenLedger.get(index)) {
            case (? token) { #ok(token.owner); };
            case (null)    { #err(#InvalidToken(tokenId)); };
        };
    };

    public shared func mintNFT (
        request : Ext.NonFungible.MintRequest,
    ) : async () {
        assert(false);
    };

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | @ext:allowance                                                        |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    public query func allowance(
        request : Ext.Allowance.Request,
    ) : async Ext.Allowance.Response {
        #err(#Other("not transferable"));
    };

    public shared({caller}) func approve(
        request : Ext.Allowance.ApproveRequest,
    ) : async () {
        return;
    };

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | 🎨 Assets                                                             |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    public shared({caller}) func uploadAsset(
        index : Ext.TokenIndex,
        asset : Asset,
    ) : async () {
        assert(_isAdmin(caller));
        assetLedger.put(index, asset);
    };
};
