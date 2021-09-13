import Array "mo:base/Array";
import Text "mo:base/Text";

import Assets "mo:assets/AssetStorage";

import Interface "Metarank";


// The compiler will complain about this whole actor until it implements MetarankInterface
// TODO: implement MetarankInterface
shared ({ caller = owner }) actor class MetaRank() : async Interface.MetarankInterface {

    // TODO: Create internal asset state (asset index, asset payload, etc.)
    // TODO: Create internal ledger state (token id, player, rank record)
    // TODO: Create Rank type (assetIndex, title, etc)

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

    // We should expose previews via HTTP
    public query func http_request(request : Assets.HttpRequest) : async Assets.HttpResponse {
            
            // Stoic uses this to request a preview of a certain token ID
            // TODO: implement this
            if (Text.contains(request.url, #text("tokenid"))) {
                return {
                    body = [];
                    headers = [];
                    status_code = 200;
                    streaming_strategy = null;
                };
            };

            return {
                body = [];
                headers = [];
                status_code = 404;
                streaming_strategy = null;
            };
    };

};