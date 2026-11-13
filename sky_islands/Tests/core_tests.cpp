#include "../Source/SkyIslands/Core/WorldModel.h"
#include <cstdlib>
#include <iostream>
#include <limits>
#include <random>
#include <sstream>
using namespace SkyCore;
static int assertions = 0;
#define CHECK(expr) do { ++assertions; if (!(expr)) { std::cerr << "FAIL line " << __LINE__ << ": " << #expr << '\n'; std::exit(1); } } while(false)
static std::string Save(const Model& m) { std::ostringstream s; CHECK(m.Serialize(s)); return s.str(); }
static Quantity Total(const Model& m, Item item) {
    Quantity total = 0;
    for (const auto& p : m.state.players) total += Get(p.second.inventory, item);
    for (const auto& f : m.state.factories) total += Get(f.second.stock, item);
    for (const auto& l : m.state.listings)
        if (!l.second.closed && l.second.kind == ListingKind::Items && l.second.item == item) total += l.second.quantity;
    for (const auto& p : m.state.parts) if (p.second.material == item) total += p.second.materialUnits;
    for (const auto& f : m.state.fasteners) if (f.second.kind == item) ++total;
    return total;
}
static void Harvesting() {
    Model m;
    CHECK(m.AddPlayer(1, 0));
    CHECK(!m.AddPlayer(1, 2)); CHECK(!m.AddPlayer(0, 0)); CHECK(!m.AddPlayer(2, -1));
    CHECK(m.SeedDeposit(1, Item::Clay, 5)); CHECK(!m.SeedDeposit(1, Item::Clay, 10));
    CHECK(!m.SeedDeposit(2, Item::Board, 10)); CHECK(!m.Harvest(1, 1, Tool::Axe));
    CHECK(m.Count(1, Item::Clay) == 0 && m.state.deposits.at(1).remaining == 5);
    CHECK(m.Harvest(1, 1, Tool::Shovel, 3));
    CHECK(m.Count(1, Item::Clay) == 3 && m.state.deposits.at(1).remaining == 2);
    const auto before = Save(m);
    CHECK(!m.Harvest(1, 1, Tool::Shovel, 3)); CHECK(!m.Harvest(1, 1, Tool::Shovel, -1));
    CHECK(Save(m) == before);
    CHECK(m.Harvest(1, 1, Tool::Shovel, 2)); CHECK(!m.Harvest(1, 1, Tool::Shovel));
    CHECK(m.SeedDeposit(2, Item::Timber, 2)); CHECK(!m.Harvest(1, 2, Tool::Pickaxe));
    CHECK(m.Harvest(1, 2, Tool::Axe));
    CHECK(m.SeedDeposit(3, Item::Ore, 1)); CHECK(!m.Harvest(1, 3, Tool::Shovel));
    CHECK(m.Harvest(1, 3, Tool::Pickaxe));
    CHECK(m.Grant(1, Item::Soil, MaxQuantity));
    CHECK(m.SeedDeposit(4, Item::Soil, 5));
    CHECK(!m.Harvest(1, 4, Tool::Shovel)); CHECK(m.state.deposits.at(4).remaining == 5);
    CHECK(!m.Grant(1, static_cast<Item>(240), 1));
}
static void Building() {
    Model m; CHECK(m.AddPlayer(1, 50)); CHECK(m.AddPlayer(2, 50));
    CHECK(m.Grant(1, Item::Board, 10)); CHECK(m.Grant(1, Item::Screw, 10));
    CHECK(MaterialCost(Item::Board, {2, .2, .03}) == 1);
    CHECK(MaterialCost(Item::Board, {4, .2, .03}) == 2);
    CHECK(m.PlacePart(1, 1, Item::Board, {2, .2, .03}, {0,0,0}));
    CHECK(m.PlacePart(1, 2, Item::Board, {4, .2, .03}, {0,0,1}));
    CHECK(m.Count(1, Item::Board) == 7);
    CHECK(Total(m, Item::Board) == 10);
    CHECK(!m.PlacePart(1, 3, Item::Board, {std::numeric_limits<double>::quiet_NaN(), .2, .03}, {}));
    CHECK(!m.PlacePart(1, 3, Item::Board, {20,20,20}, {}));
    CHECK(!m.MovePart(2, 1, {}));
    CHECK(m.MovePart(1, 1, {2,2,2}));
    CHECK(!m.Fasten(1, 1, 1, 1, Item::Screw, {}));
    CHECK(!m.Fasten(2, 1, 1, 2, Item::Screw, {}));
    CHECK(m.Fasten(1, 1, 1, 0, Item::Screw, {})); // Terrain anchor.
    CHECK(m.Fasten(1, 2, 1, 2, Item::Screw, {}));
    CHECK(m.Count(1, Item::Screw) == 8 && Total(m, Item::Screw) == 10);
    CHECK(!m.RemovePart(1, 1)); CHECK(!m.MovePart(1, 1, {}));
    CHECK(!m.RegisterHouse(1, 20, {1})); // Joint to part outside house.
    CHECK(!m.RegisterHouse(1, 20, {1,1}));
    CHECK(m.RegisterHouse(1, 20, {1,2}));
    CHECK(m.PublishHouse(1, 100, 20, 40));
    CHECK(!m.RemoveFastener(1, 1)); CHECK(!m.PublishHouse(1, 101, 20, 40));
    CHECK(m.Purchase(2, 100));
    CHECK(m.state.houses.at(20).owner == 2);
    CHECK(m.state.parts.at(1).owner == 2 && m.state.parts.at(2).owner == 2);
    CHECK(m.state.fasteners.at(1).owner == 2 && m.state.fasteners.at(2).owner == 2);
    CHECK(m.Balance(1) == 90 && m.Balance(2) == 10);
    CHECK(!m.Purchase(2, 100)); CHECK(!m.RemoveFastener(1, 1));
    CHECK(m.RemoveFastener(2, 1)); CHECK(m.RemoveFastener(2, 2));
    CHECK(Total(m, Item::Screw) == 10);
    CHECK(Model::Validate(m.state));
}
static void DestructionAndRebuilding() {
    Model m; CHECK(m.AddPlayer(1,100)); CHECK(m.AddPlayer(2,100));
    CHECK(m.Grant(1,Item::Board,4)); CHECK(m.Grant(1,Item::Screw,4));
    CHECK(m.PlacePart(1,1,Item::Board,{2,.2,.03},{}));
    CHECK(m.PlacePart(1,2,Item::Board,{2,.2,.03},{0,0,1}));
    CHECK(m.Fasten(1,1,1,0,Item::Screw,{})); CHECK(m.Fasten(1,2,1,2,Item::Screw,{}));
    CHECK(m.RegisterHouse(1,3,{1,2})); CHECK(m.PublishHouse(1,4,3,50));
    const Quantity boards = m.Count(1,Item::Board), screws = m.Count(1,Item::Screw);
    CHECK(m.DestroyPart(1));
    CHECK(m.Count(1,Item::Board)==boards && m.Count(1,Item::Screw)==screws);
    CHECK(m.state.fasteners.empty()); CHECK(!m.state.parts.count(1));
    CHECK(m.state.houses.at(3).parts.size()==1 && m.state.houses.at(3).parts.front()==2);
    CHECK(m.state.houses.at(3).listing==0 && m.state.listings.at(4).closed);
    CHECK(!m.Purchase(2,4)); CHECK(m.Balance(1)==100 && m.Balance(2)==100);
    const auto bytes = Save(m); Model restored; std::istringstream in(bytes); CHECK(restored.Deserialize(in));
    CHECK(!restored.state.parts.count(1)); CHECK(restored.state.fasteners.empty());
    CHECK(restored.PublishHouse(1,5,3,20)); CHECK(restored.DestroyPart(2));
    CHECK(restored.state.houses.empty()); CHECK(!restored.Purchase(2,5));
    const auto destroyed = Save(restored); std::istringstream input(destroyed); CHECK(m.Deserialize(input));
    CHECK(m.state.parts.empty() && m.state.houses.empty()); CHECK(!m.DestroyPart(2));
    CHECK(m.PlacePart(1,8,Item::Board,{2,.2,.03},{})); CHECK(m.RegisterHouse(1,9,{8}));
    CHECK(!m.UnregisterHouse(2,9)); CHECK(m.UnregisterHouse(1,9));
    CHECK(m.MovePart(1,8,{5,6,7})); CHECK(m.RemovePart(1,8));
    CHECK(m.Count(1,Item::Board)==boards);
}
static void Markets() {
    Model m; CHECK(m.AddPlayer(1, 100)); CHECK(m.AddPlayer(2, 200)); CHECK(m.AddPlayer(3, 100, true));
    CHECK(m.Grant(1, Item::Timber, 10));
    CHECK(!m.PublishItems(1, 1, Item::Timber, -3, 10));
    CHECK(!m.PublishItems(1, 1, Item::Timber, 3, -10));
    CHECK(m.PublishItems(1, 1, Item::Timber, 3, 30));
    CHECK(m.Count(1, Item::Timber) == 7 && Total(m, Item::Timber) == 10);
    CHECK(!m.Purchase(1, 1)); CHECK(!m.CancelListing(2, 1));
    CHECK(m.Purchase(3, 1)); // NPC pays from its own finite budget.
    CHECK(m.Balance(3) == 70 && m.Balance(1) == 130);
    CHECK(m.Count(3, Item::Timber) == 3 && Total(m, Item::Timber) == 10);
    const auto closed = Save(m);
    CHECK(!m.Purchase(2, 1)); CHECK(!m.CancelListing(1, 1));
    CHECK(!m.PublishItems(1, 1, Item::Timber, 1, 1)); CHECK(Save(m) == closed);
    CHECK(m.PublishItems(1, 2, Item::Timber, 2, 500));
    const auto before = Save(m); CHECK(!m.Purchase(2, 2)); CHECK(Save(m) == before);
    CHECK(m.CancelListing(1, 2)); CHECK(m.Count(1, Item::Timber) == 7);
    CHECK(Total(m, Item::Timber) == 10);
    CHECK(m.Grant(2, Item::Timber, MaxQuantity));
    CHECK(m.PublishItems(1, 3, Item::Timber, 1, 1));
    const auto capacity = Save(m); CHECK(!m.Purchase(2, 3)); CHECK(Save(m) == capacity);
    CHECK(m.AddPlayer(4, MaxCoins)); CHECK(m.Grant(4, Item::Stone, 1));
    CHECK(m.PublishItems(4, 4, Item::Stone, 1, 1));
    const auto rich = Save(m); CHECK(!m.Purchase(1, 4)); CHECK(Save(m) == rich);
}
static void ExchangeAndFactories() {
    Model m; CHECK(m.AddPlayer(1, 500)); CHECK(m.AddPlayer(2, 100));
    CHECK(m.Grant(1, Item::Timber, 10)); CHECK(m.Grant(2, Item::Stone, 5));
    TradeOffer a{{{Item::Timber,3}}, 10, {}}, b{{{Item::Stone,2}}, 0, {}};
    CHECK(m.Exchange(1, a, 2, b));
    CHECK(m.Count(1, Item::Timber) == 7 && m.Count(2, Item::Timber) == 3);
    CHECK(m.Count(1, Item::Stone) == 2 && m.Balance(1) == 490 && m.Balance(2) == 110);
    const auto before = Save(m);
    a.items[Item::Timber] = 500;
    CHECK(!m.Exchange(1,a,2,b)); CHECK(Save(m) == before);
    a.items[Item::Timber] = -1;
    CHECK(!m.Exchange(1,a,2,b)); CHECK(Save(m) == before);
    CHECK(m.BuyFactory(1, 1, FactoryKind::Sawmill));
    CHECK(!m.Produce(2,1)); CHECK(!m.Produce(1,1));
    CHECK(m.DepositFactory(1,1,Item::Timber,2));
    CHECK(!m.WithdrawFactory(2,1,Item::Timber,1));
    CHECK(m.Produce(1,1,2)); CHECK(Get(m.state.factories.at(1).stock,Item::Board) == 8);
    CHECK(m.WithdrawFactory(1,1,Item::Board,8)); CHECK(m.Count(1,Item::Board) == 8);
    CHECK(m.BuyFactory(1,2,FactoryKind::BrickKiln));
    CHECK(m.Grant(1,Item::Clay,4)); CHECK(m.Grant(1,Item::Sand,2)); CHECK(m.Grant(1,Item::Fuel,2));
    CHECK(m.DepositFactory(1,2,Item::Clay,4)); CHECK(m.DepositFactory(1,2,Item::Sand,2));
    const auto missing = Save(m); CHECK(!m.Produce(1,2,2)); CHECK(Save(m) == missing);
    CHECK(m.DepositFactory(1,2,Item::Fuel,2)); CHECK(m.Produce(1,2,2));
    CHECK(Get(m.state.factories.at(2).stock,Item::Brick) == 8);
    CHECK(Get(m.state.factories.at(2).stock,Item::Clay) == 0);
    CHECK(!m.Produce(1,2,-1));
    // A unique house can be exchanged once and all constituent ownership follows.
    CHECK(m.PlacePart(1,1,Item::Board,{2,.2,.03},{})); CHECK(m.RegisterHouse(1,1,{1}));
    a = {{}, 0, {1}}; b = {{}, 50, {}};
    CHECK(m.Exchange(1,a,2,b)); CHECK(m.state.parts.at(1).owner == 2);
    CHECK(!m.Exchange(1,a,2,b));
}
static void Persistence() {
    Model m; CHECK(m.AddPlayer(1,1000)); CHECK(m.AddPlayer(2,1000,true));
    CHECK(m.Grant(1,Item::Board,10)); CHECK(m.Grant(1,Item::Nail,10));
    CHECK(m.SeedDeposit(30,Item::Clay,20)); CHECK(m.Harvest(1,30,Tool::Shovel));
    CHECK(m.PlacePart(1,42,Item::Board,{2,.2,.03},{1.234,5.678,-9.123}));
    CHECK(m.Fasten(1,77,42,0,Item::Nail,{1.234,5.678,-9.123}));
    CHECK(m.RegisterHouse(1,88,{42})); CHECK(m.PublishHouse(1,99,88,100));
    CHECK(m.PublishItems(1,100,Item::Board,2,10)); CHECK(m.BuyFactory(1,4,FactoryKind::Sawmill));
    const auto bytes = Save(m);
    Model restored; std::istringstream in(bytes); CHECK(restored.Deserialize(in)); CHECK(Save(restored) == bytes);
    CHECK(restored.Purchase(2,99)); CHECK(restored.state.fasteners.at(77).owner == 2);
    const auto before = Save(restored);
    for (const auto& bad : {std::string("SKYCORE 99\n"), bytes.substr(0,bytes.size()/2), bytes+"garbage", std::string("SKYCORE 1\n-1\n"), std::string("SKYCORE 1\n99999999999999999999999999999\n")}) {
        std::istringstream input(bad); CHECK(!restored.Deserialize(input)); CHECK(Save(restored) == before);
    }
    auto corrupt = restored.state; corrupt.parts.at(42).owner = 999;
    CHECK(!restored.Restore(corrupt)); CHECK(Save(restored) == before);
    corrupt = restored.state; corrupt.players.at(1).coins = -1;
    CHECK(!restored.Restore(corrupt)); CHECK(Save(restored) == before);
    std::mt19937 random(1234);
    for (int i=0; i<300; ++i) {
        std::string fuzz(random()%150, ' ');
        for (auto& c : fuzz) c = static_cast<char>(32+random()%95);
        std::istringstream input(fuzz); CHECK(!restored.Deserialize(input));
    }
    CHECK(Save(restored) == before);
}
static void ConservationUnderTrading() {
    Model m;
    for (Id id=1;id<=8;++id) { CHECK(m.AddPlayer(id,1000,id%2==0)); CHECK(m.Grant(id,Item::Stone,100)); }
    std::mt19937 random(42);
    for (Id id=1;id<=500;++id) {
        const Id seller=1+random()%8, buyer=1+random()%8;
        if (m.Count(seller,Item::Stone) > 0 && m.PublishItems(seller,id,Item::Stone,1,1)) {
            if (!m.Purchase(buyer,id)) CHECK(m.CancelListing(seller,id));
        }
        Quantity coins=0; for (const auto& p:m.state.players) coins+=p.second.coins;
        CHECK(coins==8000); CHECK(Total(m,Item::Stone)==800); CHECK(Model::Validate(m.state));
    }
}
int main() {
    Harvesting(); Building(); DestructionAndRebuilding(); Markets(); ExchangeAndFactories(); Persistence(); ConservationUnderTrading();
    std::cout << "CORE PASS: " << assertions << " assertions; harvesting, arbitrary parts, physical connectors, market escrow, unique houses, barter, factories, bounded persistence and conservation\n";
}
