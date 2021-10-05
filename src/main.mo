import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Bool "mo:base/Bool";
import Char "mo:base/Char";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";

import Ext "mo:ext/Ext";
import Interface "mo:ext/Interface";

import Assets "mo:assets/AssetStorage";


shared ({ caller = owner }) actor class MetaRank() : async Interface.NonFungibleToken = this {

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | Asset State                                                           |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    public type Asset = {
        contentType : Text;
        payload     : [Blob];
    };

    private stable var assets : [var Asset] = [var];

    private var uploadBuffer : [Blob] = [];

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
        rankRecord : RankRecord;
    };

    type RankRecord = {
        rank    : Nat; // Gamer = 0, Strong Gamer = 1, etc.
        number  : Nat; // Player's index on the leaderboard
        score   : Nat; // Final metascore
        pctile  : Float;
        name    : Text;
        title   : Text;
    };

    type MintRequest = {
        to      : Ext.User;
        record  : RankRecord;
        metadata: ?Blob;
    };

    private stable var nextTokenId : Ext.TokenIndex = 0;
    private stable var stableTokenLedger : [(Ext.TokenIndex, Token)] = [];
    private var tokenLedger = HashMap.fromIter<Ext.TokenIndex, Token>(
        stableTokenLedger.vals(), 0, Ext.TokenIndex.equal, Ext.TokenIndex.hash,
    );

    private let tokensOfUser = HashMap.HashMap<
        Ext.AccountIdentifier, 
        [Ext.TokenIndex]
    >(0, Ext.AccountIdentifier.equal, Ext.AccountIdentifier.hash);

    private func putUserToken(
        tokenId : Ext.TokenIndex,
        token   : Token,
    ) : () {
        let tokens = switch (tokensOfUser.get(token.owner)) {
            case (null) { []; };
            case (? tk) { tk; };
        };
        tokensOfUser.put(token.owner, Array.append(tokens, [tokenId]));
    };

    for ((tokenId, token) in tokenLedger.entries()) putUserToken(tokenId, token);

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
        stableTokenLedger := Iter.toArray(tokenLedger.entries());
    };

    system func postupgrade() {
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

    // We use this to mint badges by hand after the tournament.
    // @auth: admin
    public shared({caller}) func batchMint(
        requests : [MintRequest]
    ) : async () {
        assert (_isAdmin(caller));
        for (r in Iter.fromArray(requests)) {
            await mint(r);
        };
    };

    // Allows admins to mint NFTs.
    // @auth: admin
    public shared({caller}) func mint (
        request : MintRequest,
    ) : async () {
        assert (_isAdmin(caller));
        let token = {
            createdAt = Time.now();
            owner = Ext.User.toAccountIdentifier(request.to);
            rankRecord = request.record;
        };
        tokenLedger.put(nextTokenId, token);
        putUserToken(nextTokenId, token);
        nextTokenId += 1;
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
    // | Non-standard EXT                                                       |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    public shared func userToken(user : Ext.User) : async ?Token {
        switch (tokensOfUser.get(Ext.User.toAccountIdentifier(user))) {
            case (?ids) tokenLedger.get(ids[0]);
            case (_) null;
        }
    };

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | 🎨 Assets                                                             |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    // Upload an asset in one shot.
    // @auth: admin
    public shared({caller}) func uploadAsset(
        index : Nat,
        asset : Asset,
    ) : async () {
        assert(_isAdmin(caller));
        assets[index] := asset;
    };

    // Upload some bytes into the buffer. For larger assets.
    // @auth: admin
    public shared({caller}) func uploadAssetBuffer(
        bytes : [Blob]
    ) : async () {
        assert(_isAdmin(caller));
        uploadBuffer := Array.append(uploadBuffer, bytes);
    };

    // Finalize the upload buffer into an asset.
    // @auth: admin
    public shared({caller}) func writeAssetBuffer(
        index       : Nat,
        contentType : Text
    ) : async () {
        assert(_isAdmin(caller));
        assets[index] := {
            contentType = contentType;
            payload = uploadBuffer;
        };
        uploadBuffer := [];
    };

    private func getTokenAsset(tokenIndex : Ext.TokenIndex) : Result.Result<Asset, {#token; #asset}> {
        switch(tokenLedger.get(tokenIndex)) {
            case (?token) #ok(getRankAsset(token.rankRecord));
            case null #err(#token);
        };
    };

    private func getRankAsset(record : RankRecord) : Asset {
        assets[record.rank];
    };

    // ◤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◥
    // | HTTP                                                                   |
    // ◣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◢

    public query func http_request(request : Assets.HttpRequest) : async Assets.HttpResponse {
        // Token preview
        if (Text.contains(request.url, #text("tokenid"))) {
            return preview(request);
        };

        // 404
        return http_404(null);
    };

    private func preview(request : Assets.HttpRequest) : Assets.HttpResponse {
        let tokenId = Iter.toArray(Text.tokens(request.url, #text("tokenid=")))[1];
        switch (Ext.TokenIdentifier.decode(tokenId)) {
            case (#err(err)) http_400(?"Invalid token ID.");
            case (#ok(_, tokenIndex)) {
                switch (getTokenAsset(tokenIndex)) {
                    case (#ok(asset)) ({
                        body = Blob.toArray(asset.payload[0]);
                        headers = [
                            ("Content-Type", asset.contentType),
                            ("Cache-Control", "max-age=31536000"), // Cache one year
                        ];
                        status_code = 200;
                        streaming_strategy = null;
                    });
                    case (#err(_)) http_404(null);
                };
            };
        }          
    };

    private func http_404(msg : ?Text) : Assets.HttpResponse {
        {
            body = Blob.toArray(Text.encodeUtf8(
                switch (msg) {
                    case (?msg) msg;
                    case null "Not found.";
                }
            ));
            headers = [
                ("Content-Type", "text/plain"),
            ];
            status_code = 404;
            streaming_strategy = null;
        };
    };

    private func http_400(msg : ?Text) : Assets.HttpResponse {
        {
            body = Blob.toArray(Text.encodeUtf8(
                switch (msg) {
                    case (?msg) msg;
                    case null "Bad request.";
                }
            ));
            headers = [
                ("Content-Type", "text/plain"),
            ];
            status_code = 400;
            streaming_strategy = null;
        };
    };

};
