#pragma once

// Deterministic, engine-independent authoritative gameplay rules. C++17.
// Only the server may mutate Model or load a Snapshot. RPC callers must never
// choose another player's id, mint items, set balances, or restore raw state.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <map>
#include <locale>
#include <iomanip>
#include <istream>
#include <ostream>
#include <sstream>
#include <string>
#include <set>
#include <vector>

namespace SkyCore {
using Id = std::int64_t;
using Quantity = std::int64_t;
constexpr Quantity MaxQuantity = 1000000000;
constexpr Quantity MaxCoins = 9000000000000000LL;

enum class Item : std::uint8_t {
    Soil = 0, Clay, Sand, Stone, Timber, Board, Brick, Ore, Metal, Nail, Screw, Fuel
};
enum class Tool : std::uint8_t { Shovel = 0, Axe, Pickaxe };
enum class FactoryKind : std::uint8_t { Sawmill = 0, BrickKiln, Smelter };
enum class ListingKind : std::uint8_t { Items = 0, House };
enum class Error : std::uint8_t {
    None = 0, InvalidId, AlreadyExists, NotFound, InvalidAmount, InvalidGeometry,
    WrongTool, Depleted, InsufficientItems, InsufficientCoins, Capacity,
    NotOwner, SelfTrade, Closed, Locked, Connected, InvalidState
};
struct Status {
    Error error = Error::None;
    bool Ok() const { return error == Error::None; }
    explicit operator bool() const { return Ok(); }
};
using Inventory = std::map<Item, Quantity>;
struct Vec3 { double x = 0, y = 0, z = 0; };
struct Dimensions { double length = 2, width = 0.2, height = 0.03; };
struct Player { Id id = 0; bool npc = false; Quantity coins = 0; Inventory inventory; };
struct Deposit { Id id = 0; Item item = Item::Soil; Quantity remaining = 0; };
struct Part {
    Id id = 0, owner = 0, house = 0;
    Item material = Item::Board;
    Dimensions dimensions;
    Vec3 position;
    Quantity materialUnits = 0;
};
struct Fastener {
    Id id = 0, owner = 0, partA = 0, partB = 0;
    Item kind = Item::Screw;
    Vec3 position;
};
struct House { Id id = 0, owner = 0, listing = 0; std::vector<Id> parts; };
struct Listing {
    Id id = 0, seller = 0;
    ListingKind kind = ListingKind::Items;
    Item item = Item::Soil;
    Quantity quantity = 0, price = 0;
    Id house = 0;
    bool closed = false;
};
struct Factory { Id id = 0, owner = 0; FactoryKind kind = FactoryKind::Sawmill; Inventory stock; };
struct TradeOffer { Inventory items; Quantity coins = 0; std::vector<Id> houses; };
struct Snapshot {
    std::map<Id, Player> players;
    std::map<Id, Deposit> deposits;
    std::map<Id, Part> parts;
    std::map<Id, Fastener> fasteners;
    std::map<Id, House> houses;
    std::map<Id, Listing> listings;
    std::map<Id, Factory> factories;
};

inline bool ValidItem(Item value) { return static_cast<unsigned>(value) <= static_cast<unsigned>(Item::Fuel); }
inline Quantity Get(const Inventory& inventory, Item item) {
    const auto it = inventory.find(item);
    return it == inventory.end() ? 0 : it->second;
}
inline bool ValidAmount(Quantity value) { return value > 0 && value <= MaxQuantity; }
inline bool ValidCoins(Quantity value) { return value >= 0 && value <= MaxCoins; }
inline bool ValidInventory(const Inventory& inventory) {
    for (const auto& pair : inventory)
        if (!ValidItem(pair.first) || pair.second < 0 || pair.second > MaxQuantity) return false;
    return true;
}
inline bool Finite(Vec3 value) {
    return std::isfinite(value.x) && std::isfinite(value.y) && std::isfinite(value.z)
        && std::abs(value.x) <= 10000000 && std::abs(value.y) <= 10000000 && std::abs(value.z) <= 10000000;
}
inline bool ValidDimensions(Dimensions value) {
    return std::isfinite(value.length) && std::isfinite(value.width) && std::isfinite(value.height)
        && value.length >= 0.005 && value.width >= 0.005 && value.height >= 0.005
        && value.length <= 20 && value.width <= 20 && value.height <= 20;
}
inline Quantity MaterialCost(Item item, Dimensions value) {
    if (!ValidDimensions(value)) return 0;
    double unitVolume = 0;
    switch (item) {
    case Item::Board: unitVolume = 2.0 * 0.2 * 0.03; break;
    case Item::Brick: unitVolume = 0.25 * 0.12 * 0.065; break;
    case Item::Stone: unitVolume = 0.01; break;
    case Item::Metal: unitVolume = 0.001; break;
    default: return 0;
    }
    const double units = std::ceil((value.length * value.width * value.height) / unitVolume - 1e-9);
    if (!std::isfinite(units) || units > static_cast<double>(MaxQuantity)) return 0;
    return std::max<Quantity>(1, static_cast<Quantity>(units));
}

class Model {
public:
    // Public for trusted persistence adapters. Validate before committing a load;
    // clients must never be allowed to replace or directly mutate this state.
    Snapshot state;

    Quantity Count(Id player, Item item) const {
        const auto it = state.players.find(player);
        return it == state.players.end() ? 0 : Get(it->second.inventory, item);
    }
    Quantity Balance(Id player) const {
        const auto it = state.players.find(player);
        return it == state.players.end() ? 0 : it->second.coins;
    }
    Status AddPlayer(Id id, Quantity coins, bool npc = false) {
        if (id <= 0) return {Error::InvalidId};
        if (state.players.count(id)) return {Error::AlreadyExists};
        if (!ValidCoins(coins)) return {Error::InvalidAmount};
        state.players.emplace(id, Player{id, npc, coins, {}});
        return {};
    }
    // World setup/admin only: minting is deliberately separate from player trades.
    Status Grant(Id player, Item item, Quantity quantity) {
        auto it = state.players.find(player);
        if (it == state.players.end()) return {Error::NotFound};
        if (!ValidItem(item) || !ValidAmount(quantity)) return {Error::InvalidAmount};
        if (Get(it->second.inventory, item) > MaxQuantity - quantity) return {Error::Capacity};
        it->second.inventory[item] += quantity;
        return {};
    }
    Status SeedDeposit(Id id, Item item, Quantity quantity) {
        if (id <= 0) return {Error::InvalidId};
        if (state.deposits.count(id)) return {Error::AlreadyExists};
        if (!Harvestable(item) || !ValidAmount(quantity)) return {Error::InvalidAmount};
        state.deposits.emplace(id, Deposit{id, item, quantity});
        return {};
    }
    Status Harvest(Id player, Id deposit, Tool tool, Quantity units = 1) {
        auto p = state.players.find(player);
        auto d = state.deposits.find(deposit);
        if (p == state.players.end() || d == state.deposits.end()) return {Error::NotFound};
        if (!ValidAmount(units)) return {Error::InvalidAmount};
        if (!MatchesTool(d->second.item, tool)) return {Error::WrongTool};
        if (d->second.remaining < units) return {Error::Depleted};
        if (Get(p->second.inventory, d->second.item) > MaxQuantity - units) return {Error::Capacity};
        p->second.inventory[d->second.item] += units;
        d->second.remaining -= units;
        return {};
    }
    Status PlacePart(Id player, Id id, Item material, Dimensions dimensions, Vec3 position) {
        if (id <= 0) return {Error::InvalidId};
        if (state.parts.count(id)) return {Error::AlreadyExists};
        auto p = state.players.find(player);
        if (p == state.players.end()) return {Error::NotFound};
        const Quantity units = MaterialCost(material, dimensions);
        if (units == 0 || !Finite(position)) return {Error::InvalidGeometry};
        if (Get(p->second.inventory, material) < units) return {Error::InsufficientItems};
        p->second.inventory[material] -= units;
        state.parts.emplace(id, Part{id, player, 0, material, dimensions, position, units});
        return {};
    }
    Status MovePart(Id player, Id id, Vec3 position) {
        auto p = state.parts.find(id);
        if (p == state.parts.end()) return {Error::NotFound};
        if (p->second.owner != player) return {Error::NotOwner};
        if (!Finite(position)) return {Error::InvalidGeometry};
        if (p->second.house || HasFasteners(id)) return {Error::Connected};
        p->second.position = position;
        return {};
    }
    Status RemovePart(Id player, Id id) {
        auto part = state.parts.find(id);
        auto p = state.players.find(player);
        if (part == state.parts.end() || p == state.players.end()) return {Error::NotFound};
        if (part->second.owner != player) return {Error::NotOwner};
        if (part->second.house || HasFasteners(id)) return {Error::Connected};
        if (Get(p->second.inventory, part->second.material) > MaxQuantity - part->second.materialUnits) return {Error::Capacity};
        p->second.inventory[part->second.material] += part->second.materialUnits;
        state.parts.erase(part);
        return {};
    }
    // Authority-only damage path; the caller validates the actual hit and damage.
    // Destroyed construction never refunds material or loose fasteners.
    Status DestroyPart(Id id) {
        const auto part = state.parts.find(id);
        if (part == state.parts.end()) return {Error::NotFound};
        const Id house = part->second.house;
        for (auto it = state.fasteners.begin(); it != state.fasteners.end();) {
            if (it->second.partA == id || it->second.partB == id) it = state.fasteners.erase(it);
            else ++it;
        }
        if (house != 0) {
            auto h = state.houses.find(house);
            if (h != state.houses.end()) {
                if (h->second.listing != 0) {
                    const auto listing = state.listings.find(h->second.listing);
                    if (listing != state.listings.end()) listing->second.closed = true;
                    h->second.listing = 0;
                }
                auto& pieces = h->second.parts;
                pieces.erase(std::remove(pieces.begin(), pieces.end(), id), pieces.end());
                if (pieces.empty()) state.houses.erase(h);
            }
        }
        state.parts.erase(part);
        return {};
    }
    // Release a house assembly for rebuilding. Existing real joints remain;
    // remove individual fasteners before moving or recovering connected pieces.
    Status UnregisterHouse(Id player, Id id) {
        auto h = state.houses.find(id);
        if (h == state.houses.end()) return {Error::NotFound};
        if (h->second.owner != player) return {Error::NotOwner};
        if (h->second.listing) return {Error::Locked};
        for (const Id part : h->second.parts) state.parts.at(part).house = 0;
        state.houses.erase(h);
        return {};
    }
    Status Fasten(Id player, Id id, Id partA, Id partB, Item kind, Vec3 position) {
        if (id <= 0) return {Error::InvalidId};
        if (state.fasteners.count(id)) return {Error::AlreadyExists};
        auto p = state.players.find(player);
        auto a = state.parts.find(partA), b = state.parts.find(partB);
        if (p == state.players.end() || a == state.parts.end() || (partB != 0 && b == state.parts.end())) return {Error::NotFound};
        if (partA == partB || (kind != Item::Nail && kind != Item::Screw) || !Finite(position)) return {Error::InvalidGeometry};
        if (a->second.owner != player || (partB != 0 && b->second.owner != player)) return {Error::NotOwner};
        if (partB != 0 && a->second.house != b->second.house) return {Error::Connected};
        if (HouseLocked(a->second.house)) return {Error::Locked};
        if (Get(p->second.inventory, kind) < 1) return {Error::InsufficientItems};
        p->second.inventory[kind] -= 1;
        state.fasteners.emplace(id, Fastener{id, player, partA, partB, kind, position});
        return {};
    }
    Status RemoveFastener(Id player, Id id) {
        auto fastener = state.fasteners.find(id);
        auto p = state.players.find(player);
        if (fastener == state.fasteners.end() || p == state.players.end()) return {Error::NotFound};
        if (fastener->second.owner != player) return {Error::NotOwner};
        const auto a = state.parts.find(fastener->second.partA);
        if (a == state.parts.end()) return {Error::InvalidState};
        if (HouseLocked(a->second.house)) return {Error::Locked};
        if (Get(p->second.inventory, fastener->second.kind) == MaxQuantity) return {Error::Capacity};
        p->second.inventory[fastener->second.kind] += 1;
        state.fasteners.erase(fastener);
        return {};
    }
    Status RegisterHouse(Id player, Id id, const std::vector<Id>& parts) {
        if (id <= 0) return {Error::InvalidId};
        if (state.houses.count(id)) return {Error::AlreadyExists};
        if (!state.players.count(player)) return {Error::NotFound};
        if (parts.empty() || parts.size() > 100000) return {Error::InvalidAmount};
        const std::set<Id> selected(parts.begin(), parts.end());
        if (selected.size() != parts.size()) return {Error::InvalidAmount};
        for (const Id part : parts) {
            const auto p = state.parts.find(part);
            if (p == state.parts.end()) return {Error::NotFound};
            if (p->second.owner != player) return {Error::NotOwner};
            if (p->second.house) return {Error::Locked};
        }
        for (const auto& f : state.fasteners)
            if (f.second.partB != 0 && ((selected.count(f.second.partA) != 0) != (selected.count(f.second.partB) != 0))) return {Error::Connected};
        state.houses.emplace(id, House{id, player, 0, parts});
        for (const Id part : parts) state.parts.at(part).house = id;
        return {};
    }
    // Escrow removes items from seller inventory immediately. Closed listings stay
    // archived, preventing stale/replayed purchases or reuse of a listing id.
    Status PublishItems(Id seller, Id listing, Item item, Quantity quantity, Quantity price) {
        auto p = state.players.find(seller);
        if (p == state.players.end()) return {Error::NotFound};
        if (listing <= 0) return {Error::InvalidId};
        if (state.listings.count(listing)) return {Error::AlreadyExists};
        if (!ValidItem(item) || !ValidAmount(quantity) || price <= 0 || !ValidCoins(price)) return {Error::InvalidAmount};
        if (Get(p->second.inventory, item) < quantity) return {Error::InsufficientItems};
        p->second.inventory[item] -= quantity;
        state.listings.emplace(listing, Listing{listing, seller, ListingKind::Items, item, quantity, price, 0, false});
        return {};
    }
    Status PublishHouse(Id seller, Id listing, Id house, Quantity price) {
        if (listing <= 0) return {Error::InvalidId};
        if (state.listings.count(listing)) return {Error::AlreadyExists};
        auto h = state.houses.find(house);
        if (h == state.houses.end() || !state.players.count(seller)) return {Error::NotFound};
        if (h->second.owner != seller) return {Error::NotOwner};
        if (h->second.listing) return {Error::Locked};
        if (price <= 0 || !ValidCoins(price)) return {Error::InvalidAmount};
        state.listings.emplace(listing, Listing{listing, seller, ListingKind::House, Item::Soil, 0, price, house, false});
        h->second.listing = listing;
        return {};
    }
    Status Purchase(Id buyer, Id listing) {
        auto l = state.listings.find(listing);
        auto b = state.players.find(buyer);
        if (l == state.listings.end() || b == state.players.end()) return {Error::NotFound};
        if (l->second.closed) return {Error::Closed};
        const auto s = state.players.find(l->second.seller);
        if (s == state.players.end()) return {Error::InvalidState};
        if (buyer == l->second.seller) return {Error::SelfTrade};
        if (b->second.coins < l->second.price) return {Error::InsufficientCoins};
        if (s->second.coins > MaxCoins - l->second.price) return {Error::Capacity};
        if (l->second.kind == ListingKind::Items) {
            if (Get(b->second.inventory, l->second.item) > MaxQuantity - l->second.quantity) return {Error::Capacity};
        } else {
            const auto h = state.houses.find(l->second.house);
            if (h == state.houses.end() || h->second.owner != l->second.seller || h->second.listing != listing) return {Error::InvalidState};
        }
        // All validations occur before any ownership, inventory or money changes.
        b->second.coins -= l->second.price;
        s->second.coins += l->second.price;
        if (l->second.kind == ListingKind::Items) b->second.inventory[l->second.item] += l->second.quantity;
        else { TransferHouse(l->second.house, buyer); state.houses.at(l->second.house).listing = 0; }
        l->second.closed = true;
        return {};
    }
    Status CancelListing(Id seller, Id listing) {
        auto l = state.listings.find(listing);
        auto p = state.players.find(seller);
        if (l == state.listings.end() || p == state.players.end()) return {Error::NotFound};
        if (l->second.seller != seller) return {Error::NotOwner};
        if (l->second.closed) return {Error::Closed};
        if (l->second.kind == ListingKind::Items) {
            if (Get(p->second.inventory, l->second.item) > MaxQuantity - l->second.quantity) return {Error::Capacity};
            p->second.inventory[l->second.item] += l->second.quantity;
        } else state.houses.at(l->second.house).listing = 0;
        l->second.closed = true;
        return {};
    }
    Status Exchange(Id first, const TradeOffer& firstOffer, Id second, const TradeOffer& secondOffer) {
        if (first == second) return {Error::SelfTrade};
        auto a = state.players.find(first), b = state.players.find(second);
        if (a == state.players.end() || b == state.players.end()) return {Error::NotFound};
        const Status va = ValidateOffer(first, firstOffer), vb = ValidateOffer(second, secondOffer);
        if (!va) return va;
        if (!vb) return vb;
        Player nextA = a->second, nextB = b->second;
        const Status ia = ApplyOffer(nextA, firstOffer, secondOffer);
        if (!ia) return ia;
        const Status ib = ApplyOffer(nextB, secondOffer, firstOffer);
        if (!ib) return ib;
        a->second = nextA; b->second = nextB;
        for (const Id h : firstOffer.houses) TransferHouse(h, second);
        for (const Id h : secondOffer.houses) TransferHouse(h, first);
        return {};
    }
    static Quantity FactoryPrice(FactoryKind kind) {
        switch (kind) {
        case FactoryKind::Sawmill: return 120;
        case FactoryKind::BrickKiln: return 160;
        case FactoryKind::Smelter: return 200;
        }
        return 0;
    }
    Status BuyFactory(Id player, Id id, FactoryKind kind) {
        if (id <= 0) return {Error::InvalidId};
        if (state.factories.count(id)) return {Error::AlreadyExists};
        auto p = state.players.find(player);
        if (p == state.players.end()) return {Error::NotFound};
        const Quantity price = FactoryPrice(kind);
        if (price <= 0) return {Error::InvalidAmount};
        if (p->second.coins < price) return {Error::InsufficientCoins};
        p->second.coins -= price; // Explicit NPC purchase sink, not a player trade.
        state.factories.emplace(id, Factory{id, player, kind, {}});
        return {};
    }
    Status DepositFactory(Id player, Id factory, Item item, Quantity quantity) {
        return TransferFactoryStock(player, factory, item, quantity, true);
    }
    Status WithdrawFactory(Id player, Id factory, Item item, Quantity quantity) {
        return TransferFactoryStock(player, factory, item, quantity, false);
    }
    Status Produce(Id player, Id factory, Quantity batches = 1) {
        auto f = state.factories.find(factory);
        if (f == state.factories.end() || !state.players.count(player)) return {Error::NotFound};
        if (f->second.owner != player) return {Error::NotOwner};
        if (!ValidAmount(batches) || batches > MaxQuantity / 4) return {Error::InvalidAmount};
        Inventory consumed, produced;
        switch (f->second.kind) {
        case FactoryKind::Sawmill: consumed = {{Item::Timber, batches}}; produced = {{Item::Board, 4*batches}}; break;
        case FactoryKind::BrickKiln: consumed = {{Item::Clay, 2*batches}, {Item::Sand, batches}, {Item::Fuel, batches}}; produced = {{Item::Brick, 4*batches}}; break;
        case FactoryKind::Smelter: consumed = {{Item::Ore, 2*batches}, {Item::Fuel, batches}}; produced = {{Item::Metal, batches}}; break;
        default: return {Error::InvalidState};
        }
        for (const auto& input : consumed)
            if (Get(f->second.stock, input.first) < input.second) return {Error::InsufficientItems};
        for (const auto& output : produced)
            if (Get(f->second.stock, output.first) > MaxQuantity - output.second) return {Error::Capacity};
        for (const auto& input : consumed) f->second.stock[input.first] -= input.second;
        for (const auto& output : produced) f->second.stock[output.first] += output.second;
        return {};
    }
    // Treat a failed validation as a rejected save and preserve the live world.
    Status Restore(const Snapshot& snapshot) {
        const Status valid = Validate(snapshot);
        if (!valid) return valid;
        state = snapshot;
        return {};
    }
    static Status Validate(const Snapshot& s) {
        const std::size_t sizes[] = {s.players.size(), s.deposits.size(), s.parts.size(), s.fasteners.size(), s.houses.size(), s.listings.size(), s.factories.size()};
        std::size_t records = 0;
        for (const auto size : sizes) {
            if (size > 100000 || size > 500000 - records) return {Error::InvalidState};
            records += size;
        }
        for (const auto& pair : s.players) {
            if (pair.second.inventory.size() > 500000 - records) return {Error::InvalidState};
            records += pair.second.inventory.size();
            const auto& p = pair.second;
            if (pair.first <= 0 || p.id != pair.first || !ValidCoins(p.coins) || !ValidInventory(p.inventory)) return {Error::InvalidState};
        }
        for (const auto& pair : s.deposits) {
            const auto& d = pair.second;
            if (pair.first <= 0 || d.id != pair.first || !Harvestable(d.item) || d.remaining < 0 || d.remaining > MaxQuantity) return {Error::InvalidState};
        }
        for (const auto& pair : s.parts) {
            const auto& p = pair.second;
            if (pair.first <= 0 || p.id != pair.first || !s.players.count(p.owner) || !Finite(p.position)
                || MaterialCost(p.material, p.dimensions) != p.materialUnits || p.materialUnits <= 0) return {Error::InvalidState};
            if (p.house) {
                const auto h = s.houses.find(p.house);
                if (h == s.houses.end() || h->second.owner != p.owner || std::count(h->second.parts.begin(), h->second.parts.end(), p.id) != 1) return {Error::InvalidState};
            }
        }
        for (const auto& pair : s.fasteners) {
            const auto& f = pair.second;
            const auto a = s.parts.find(f.partA), b = s.parts.find(f.partB);
            if (pair.first <= 0 || f.id != pair.first || f.partA == f.partB || !Finite(f.position)
                || (f.kind != Item::Nail && f.kind != Item::Screw) || a == s.parts.end() || (f.partB != 0 && b == s.parts.end())
                || a->second.owner != f.owner || (f.partB != 0 && (b->second.owner != f.owner || a->second.house != b->second.house))) return {Error::InvalidState};
        }
        for (const auto& pair : s.houses) {
            const auto& h = pair.second;
            if (pair.first <= 0 || h.id != pair.first || !s.players.count(h.owner) || h.parts.empty() || h.parts.size() > 100000 || h.parts.size() > 500000 - records) return {Error::InvalidState};
            records += h.parts.size();
            const std::set<Id> unique(h.parts.begin(), h.parts.end());
            if (unique.size() != h.parts.size()) return {Error::InvalidState};
            for (const Id part : h.parts) {
                const auto p = s.parts.find(part);
                if (p == s.parts.end() || p->second.house != h.id || p->second.owner != h.owner) return {Error::InvalidState};
            }
            if (h.listing) {
                const auto l = s.listings.find(h.listing);
                if (l == s.listings.end() || l->second.closed || l->second.kind != ListingKind::House
                    || l->second.house != h.id || l->second.seller != h.owner) return {Error::InvalidState};
            }
        }
        for (const auto& pair : s.listings) {
            const auto& l = pair.second;
            if (pair.first <= 0 || l.id != pair.first || !s.players.count(l.seller) || !ValidItem(l.item) || l.price <= 0 || !ValidCoins(l.price)) return {Error::InvalidState};
            if (l.kind == ListingKind::Items) {
                if (!ValidItem(l.item) || !ValidAmount(l.quantity) || l.house != 0) return {Error::InvalidState};
            } else if (l.kind == ListingKind::House) {
                if (l.quantity != 0 || l.house <= 0) return {Error::InvalidState};
                if (!l.closed) {
                    const auto h = s.houses.find(l.house);
                    if (h == s.houses.end() || h->second.owner != l.seller || h->second.listing != l.id) return {Error::InvalidState};
                }
            } else return {Error::InvalidState};
        }
        for (const auto& pair : s.factories) {
            const auto& f = pair.second;
            if (f.stock.size() > 500000 - records) return {Error::InvalidState};
            records += f.stock.size();
            if (pair.first <= 0 || f.id != pair.first || !s.players.count(f.owner) || FactoryPrice(f.kind) <= 0 || !ValidInventory(f.stock)) return {Error::InvalidState};
        }
        return {};
    }

    // Text format uses only numeric identifiers, stable enum values and metres.
    // 16 MiB and aggregate record bounds keep malformed saves finite to parse.
    static constexpr std::size_t MaxSaveBytes = 16 * 1024 * 1024;
    Status Serialize(std::ostream& output) const {
        if (!Validate(state)) return {Error::InvalidState};
        std::ostringstream out;
        out.imbue(std::locale::classic());
        out << std::setprecision(17) << "SKYCORE 1\n";
        out << state.players.size() << '\n';
        for (const auto& e : state.players) {
            const auto& p = e.second;
            out << p.id << ' ' << int(p.npc) << ' ' << p.coins << ' ';
            WriteInventory(out, p.inventory); out << '\n';
        }
        out << state.deposits.size() << '\n';
        for (const auto& e : state.deposits) {
            const auto& d = e.second;
            out << d.id << ' ' << int(d.item) << ' ' << d.remaining << '\n';
        }
        out << state.parts.size() << '\n';
        for (const auto& e : state.parts) {
            const auto& p = e.second;
            out << p.id << ' ' << p.owner << ' ' << p.house << ' ' << int(p.material) << ' '
                << p.dimensions.length << ' ' << p.dimensions.width << ' ' << p.dimensions.height << ' '
                << p.position.x << ' ' << p.position.y << ' ' << p.position.z << ' ' << p.materialUnits << '\n';
        }
        out << state.fasteners.size() << '\n';
        for (const auto& e : state.fasteners) {
            const auto& f = e.second;
            out << f.id << ' ' << f.owner << ' ' << f.partA << ' ' << f.partB << ' ' << int(f.kind) << ' '
                << f.position.x << ' ' << f.position.y << ' ' << f.position.z << '\n';
        }
        out << state.houses.size() << '\n';
        for (const auto& e : state.houses) {
            const auto& h = e.second;
            out << h.id << ' ' << h.owner << ' ' << h.listing << ' ' << h.parts.size();
            for (const Id p : h.parts) out << ' ' << p;
            out << '\n';
        }
        out << state.listings.size() << '\n';
        for (const auto& e : state.listings) {
            const auto& l = e.second;
            out << l.id << ' ' << l.seller << ' ' << int(l.kind) << ' ' << int(l.item) << ' '
                << l.quantity << ' ' << l.price << ' ' << l.house << ' ' << int(l.closed) << '\n';
        }
        out << state.factories.size() << '\n';
        for (const auto& e : state.factories) {
            const auto& f = e.second;
            out << f.id << ' ' << f.owner << ' ' << int(f.kind) << ' ';
            WriteInventory(out, f.stock); out << '\n';
        }
        const std::string bytes = out.str();
        if (bytes.size() > MaxSaveBytes) return {Error::Capacity};
        output << bytes;
        return output ? Status{} : Status{Error::InvalidState};
    }
    Status Deserialize(std::istream& input) {
        std::string bytes;
        char buffer[4096];
        while (input) {
            input.read(buffer, sizeof(buffer));
            const auto count = static_cast<std::size_t>(input.gcount());
            if (count > MaxSaveBytes - bytes.size()) return {Error::Capacity};
            bytes.append(buffer, count);
        }
        if (input.bad()) return {Error::InvalidState};
        std::istringstream in(bytes);
        in.imbue(std::locale::classic());
        std::string magic;
        unsigned version = 0;
        if (!(in >> magic >> version) || magic != "SKYCORE" || version != 1) return {Error::InvalidState};
        Snapshot next;
        std::size_t budget = 500000, count = 0;
        if (!ReadCount(in, count, budget)) return {Error::InvalidState};
        for (std::size_t i = 0; i < count; ++i) {
            Player p; int npc = 0;
            if (!(in >> p.id >> npc >> p.coins) || (npc != 0 && npc != 1) || !ReadInventory(in, p.inventory, budget)) return {Error::InvalidState};
            p.npc = npc != 0;
            if (!next.players.emplace(p.id, p).second) return {Error::InvalidState};
        }
        if (!ReadCount(in, count, budget)) return {Error::InvalidState};
        for (std::size_t i = 0; i < count; ++i) {
            Deposit d; unsigned item = 0;
            if (!(in >> d.id >> item >> d.remaining) || item > unsigned(Item::Fuel)) return {Error::InvalidState};
            d.item = static_cast<Item>(item);
            if (!next.deposits.emplace(d.id, d).second) return {Error::InvalidState};
        }
        if (!ReadCount(in, count, budget)) return {Error::InvalidState};
        for (std::size_t i = 0; i < count; ++i) {
            Part p; unsigned item = 0;
            if (!(in >> p.id >> p.owner >> p.house >> item >> p.dimensions.length >> p.dimensions.width >> p.dimensions.height
                >> p.position.x >> p.position.y >> p.position.z >> p.materialUnits) || item > unsigned(Item::Fuel)) return {Error::InvalidState};
            p.material = static_cast<Item>(item);
            if (!next.parts.emplace(p.id, p).second) return {Error::InvalidState};
        }
        if (!ReadCount(in, count, budget)) return {Error::InvalidState};
        for (std::size_t i = 0; i < count; ++i) {
            Fastener f; unsigned kind = 0;
            if (!(in >> f.id >> f.owner >> f.partA >> f.partB >> kind >> f.position.x >> f.position.y >> f.position.z)
                || kind > unsigned(Item::Fuel)) return {Error::InvalidState};
            f.kind = static_cast<Item>(kind);
            if (!next.fasteners.emplace(f.id, f).second) return {Error::InvalidState};
        }
        if (!ReadCount(in, count, budget)) return {Error::InvalidState};
        for (std::size_t i = 0; i < count; ++i) {
            House h; std::size_t parts = 0;
            if (!(in >> h.id >> h.owner >> h.listing) || !ReadCount(in, parts, budget)) return {Error::InvalidState};
            for (std::size_t j = 0; j < parts; ++j) {
                Id id = 0; if (!(in >> id)) return {Error::InvalidState};
                h.parts.push_back(id);
            }
            if (!next.houses.emplace(h.id, h).second) return {Error::InvalidState};
        }
        if (!ReadCount(in, count, budget)) return {Error::InvalidState};
        for (std::size_t i = 0; i < count; ++i) {
            Listing l; unsigned kind = 0, item = 0; int closed = 0;
            if (!(in >> l.id >> l.seller >> kind >> item >> l.quantity >> l.price >> l.house >> closed)
                || kind > unsigned(ListingKind::House) || item > unsigned(Item::Fuel) || (closed != 0 && closed != 1)) return {Error::InvalidState};
            l.kind = static_cast<ListingKind>(kind); l.item = static_cast<Item>(item); l.closed = closed != 0;
            if (!next.listings.emplace(l.id, l).second) return {Error::InvalidState};
        }
        if (!ReadCount(in, count, budget)) return {Error::InvalidState};
        for (std::size_t i = 0; i < count; ++i) {
            Factory f; unsigned kind = 0;
            if (!(in >> f.id >> f.owner >> kind) || kind > unsigned(FactoryKind::Smelter) || !ReadInventory(in, f.stock, budget)) return {Error::InvalidState};
            f.kind = static_cast<FactoryKind>(kind);
            if (!next.factories.emplace(f.id, f).second) return {Error::InvalidState};
        }
        in >> std::ws;
        if (!in.eof()) return {Error::InvalidState};
        return Restore(next);
    }

private:
    static void WriteInventory(std::ostream& out, const Inventory& items) {
        out << items.size();
        for (const auto& item : items) out << ' ' << int(item.first) << ' ' << item.second;
    }
    static bool ReadCount(std::istream& in, std::size_t& count, std::size_t& budget) {
        std::int64_t n = 0;
        if (!(in >> n) || n < 0 || n > 100000 || static_cast<std::size_t>(n) > budget) return false;
        count = static_cast<std::size_t>(n); budget -= count; return true;
    }
    static bool ReadInventory(std::istream& in, Inventory& items, std::size_t& budget) {
        std::size_t count = 0;
        if (!ReadCount(in, count, budget) || count > 12) return false;
        for (std::size_t i = 0; i < count; ++i) {
            unsigned kind = 0; Quantity quantity = 0;
            if (!(in >> kind >> quantity) || kind > unsigned(Item::Fuel) || quantity < 0 || quantity > MaxQuantity) return false;
            if (!items.emplace(static_cast<Item>(kind), quantity).second) return false;
        }
        return true;
    }
    static bool Harvestable(Item item) {
        return item == Item::Soil || item == Item::Clay || item == Item::Sand || item == Item::Stone || item == Item::Timber || item == Item::Ore;
    }
    static bool MatchesTool(Item item, Tool tool) {
        if (item == Item::Timber) return tool == Tool::Axe;
        if (item == Item::Stone || item == Item::Ore) return tool == Tool::Pickaxe;
        return (item == Item::Soil || item == Item::Clay || item == Item::Sand) && tool == Tool::Shovel;
    }
    bool HasFasteners(Id part) const {
        for (const auto& f : state.fasteners)
            if (f.second.partA == part || f.second.partB == part) return true;
        return false;
    }
    bool HouseLocked(Id house) const {
        const auto h = state.houses.find(house);
        return house && h != state.houses.end() && h->second.listing;
    }
    void TransferHouse(Id house, Id owner) {
        auto& h = state.houses.at(house);
        h.owner = owner;
        for (const Id part : h.parts) state.parts.at(part).owner = owner;
        for (auto& f : state.fasteners)
            if (state.parts.at(f.second.partA).house == house) f.second.owner = owner;
    }
    Status ValidateOffer(Id player, const TradeOffer& offer) const {
        if (!ValidCoins(offer.coins) || !ValidInventory(offer.items)) return {Error::InvalidAmount};
        const auto& p = state.players.at(player);
        if (p.coins < offer.coins) return {Error::InsufficientCoins};
        for (const auto& item : offer.items)
            if (!ValidAmount(item.second)) return {Error::InvalidAmount};
            else if (Get(p.inventory, item.first) < item.second) return {Error::InsufficientItems};
        const std::set<Id> unique(offer.houses.begin(), offer.houses.end());
        if (unique.size() != offer.houses.size()) return {Error::InvalidAmount};
        for (const Id house : offer.houses) {
            const auto h = state.houses.find(house);
            if (h == state.houses.end()) return {Error::NotFound};
            if (h->second.owner != player) return {Error::NotOwner};
            if (h->second.listing) return {Error::Locked};
        }
        return {};
    }
    static Status ApplyOffer(Player& player, const TradeOffer& outgoing, const TradeOffer& incoming) {
        player.coins -= outgoing.coins;
        if (player.coins > MaxCoins - incoming.coins) return {Error::Capacity};
        player.coins += incoming.coins;
        for (const auto& item : outgoing.items) player.inventory[item.first] -= item.second;
        for (const auto& item : incoming.items) {
            if (Get(player.inventory, item.first) > MaxQuantity - item.second) return {Error::Capacity};
            player.inventory[item.first] += item.second;
        }
        return {};
    }
    Status TransferFactoryStock(Id player, Id factory, Item item, Quantity quantity, bool deposit) {
        auto p = state.players.find(player);
        auto f = state.factories.find(factory);
        if (p == state.players.end() || f == state.factories.end()) return {Error::NotFound};
        if (f->second.owner != player) return {Error::NotOwner};
        if (!ValidItem(item) || !ValidAmount(quantity)) return {Error::InvalidAmount};
        Inventory& source = deposit ? p->second.inventory : f->second.stock;
        Inventory& destination = deposit ? f->second.stock : p->second.inventory;
        if (Get(source, item) < quantity) return {Error::InsufficientItems};
        if (Get(destination, item) > MaxQuantity - quantity) return {Error::Capacity};
        source[item] -= quantity; destination[item] += quantity;
        return {};
    }
};
} // namespace SkyCore
