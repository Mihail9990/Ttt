#include "SkyWorld.h"
#include "Core/IslandField.h"
#include "Engine/World.h"
#include "Engine/StaticMesh.h"
#include "Engine/DamageEvents.h"
#include "SkyCharacter.h"
#include "SkyIsland.h"
#include "SkyBuildPart.h"
#include "SkySave.h"
#include "Components/StaticMeshComponent.h"
#include "Materials/MaterialInterface.h"
#include "EngineUtils.h"
#include "GameFramework/PlayerState.h"
#include "Net/UnrealNetwork.h"
#include "Kismet/GameplayStatics.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "UObject/ConstructorHelpers.h"
#include <sstream>
#include <limits>
namespace {
constexpr int64 Trader=900000;
SkyCore::Vec3 CorePoint(FVector P){return {P.X/100.,P.Y/100.,P.Z/100.};}
FString StatusText(SkyCore::Status S){return S?TEXT("Done"):FString::Printf(TEXT("Action rejected (%d): check materials, tool or ownership."),(int)S.error);}
TSharedRef<FJsonObject> VectorJson(FVector V){auto O=MakeShared<FJsonObject>();O->SetNumberField("x",V.X);O->SetNumberField("y",V.Y);O->SetNumberField("z",V.Z);return O;}
FVector ReadVector(const TSharedPtr<FJsonObject>& O){double X,Y,Z;if(!O.IsValid()||!O->TryGetNumberField(TEXT("x"),X)||!O->TryGetNumberField(TEXT("y"),Y)||!O->TryGetNumberField(TEXT("z"),Z))return FVector(std::numeric_limits<double>::quiet_NaN());return FVector(X,Y,Z);}
}
ASkyResource::ASkyResource(){
    bReplicates=true;SetReplicateMovement(true);
    Mesh=CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Resource"));RootComponent=Mesh;
    static ConstructorHelpers::FObjectFinder<UStaticMesh> Shape(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));Mesh->SetStaticMesh(Shape.Object);
    Mesh->SetCollisionProfileName(TEXT("BlockAll"));Mesh->SetIsReplicated(true);
}
void ASkyResource::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& Out)const{
    Super::GetLifetimeReplicatedProps(Out);DOREPLIFETIME(ASkyResource,Deposit);DOREPLIFETIME(ASkyResource,Resource);DOREPLIFETIME(ASkyResource,Remaining);
}
ASkyWorld::ASkyWorld(){bReplicates=true;bAlwaysRelevant=true;PrimaryActorTick.bCanEverTick=true;NetUpdateFrequency=5;}
ASkyWorld* ASkyWorld::Find(UWorld* W){if(!W)return nullptr;for(TActorIterator<ASkyWorld>I(W);I;++I)return *I;return nullptr;}
void ASkyWorld::BeginPlay(){Super::BeginPlay();if(HasAuthority()){RestoreWorld();SeedScene();PublishOffers();}}
void ASkyWorld::EndPlay(const EEndPlayReason::Type R){if(HasAuthority())SaveWorld();Super::EndPlay(R);}
void ASkyWorld::Tick(float Delta){Super::Tick(Delta);if(!HasAuthority())return;SaveClock+=Delta;if(SaveClock>=30){SaveClock=0;SaveWorld();}}
void ASkyWorld::SeedScene(){
    const FVector Locations[]={FVector(0,0,0),FVector(6500,1500,1000),FVector(-6000,5000,1600)};
    // Saved islands have already been restored; all random decoration uses fixed seeds.
    if(Islands.IsEmpty())for(int32 I=0;I<3;++I){auto* A=GetWorld()->SpawnActor<ASkyIsland>(Locations[I],FRotator::ZeroRotator);if(!A){CanSave=false;UE_LOG(LogTemp,Error,TEXT("Island spawn failed."));return;}A->Initialize(41+I*7,I?1800:2400);Islands.Add(A);}
    if(!Model.state.players.count(Trader)){
        Model.AddPlayer(Trader,5000,true);
        for(int32 N=0;N<=11;++N)Model.Grant(Trader,static_cast<SkyCore::Item>(N),200);
        for(auto Offer: {SkyCore::Item::Board,SkyCore::Item::Brick,SkyCore::Item::Nail,SkyCore::Item::Screw,SkyCore::Item::Fuel,SkyCore::Item::Sand})
            Model.PublishItems(Trader,NextId++,Offer,10,Offer==SkyCore::Item::Board?25:15);
    }
    FRandomStream Random(144);
    for(int32 I=0;I<18;++I){
        const int64 Deposit=100+I;
        if(!Model.state.deposits.count(Deposit))Model.SeedDeposit(Deposit,SkyCore::Item::Timber,12);
        const auto& D=Model.state.deposits.at(Deposit);
        const float Angle=Random.FRandRange(0,2*PI);const float R=Random.FRandRange(1000,1900);
        FVector Point(FMath::Cos(Angle)*R,FMath::Sin(Angle)*R,600);
        while(Point.Z>-1400 && Islands[0]->DensityAtWorld(Point)<=0)Point.Z-=20;
        Point.Z+=5;
        if(D.remaining<=0)continue;
        auto* Tree=GetWorld()->SpawnActor<ASkyResource>(Point,FRotator::ZeroRotator);if(!Tree)continue;Tree->Deposit=Deposit;Tree->Resource=(int32)SkyCore::Item::Timber;Tree->Remaining=(int32)D.remaining;
        if(auto* Mesh=LoadObject<UStaticMesh>(nullptr,TEXT("/Game/Art/Nature/SM_Tree.SM_Tree"))){Tree->Mesh->SetStaticMesh(Mesh);Tree->SetActorScale3D(FVector(1));}
        else Tree->SetActorScale3D(FVector(.4,.4,3));
        Tree->Mesh->SetCullDistance(9000);
    }
    FRandomStream RockRandom(782);
    for(int32 I=0;I<6;++I){
        const int64 Deposit=200+I;const auto Item=I%3==0?SkyCore::Item::Ore:SkyCore::Item::Stone;
        if(!Model.state.deposits.count(Deposit))Model.SeedDeposit(Deposit,Item,10);
        const float Angle=RockRandom.FRandRange(0,2*PI),Radius=RockRandom.FRandRange(600,1700);
        FVector Point(FMath::Cos(Angle)*Radius,FMath::Sin(Angle)*Radius,600);
        while(Point.Z>-1400&&Islands[0]->DensityAtWorld(Point)<=0)Point.Z-=20;
        const auto& D=Model.state.deposits.at(Deposit);if(D.remaining<=0)continue;
        auto* Rock=GetWorld()->SpawnActor<ASkyResource>(Point,FRotator(0,I*53,0));if(!Rock)continue;
        Rock->Deposit=Deposit;Rock->Resource=(int32)Item;Rock->Remaining=(int32)D.remaining;
        if(auto* M=LoadObject<UStaticMesh>(nullptr,TEXT("/Game/Art/Nature/SM_Rock.SM_Rock")))Rock->Mesh->SetStaticMesh(M);
        Rock->SetActorScale3D(FVector(.8));Rock->Mesh->SetCullDistance(9000);
    }
    WorldStatus=CanSave?TEXT("Early UE5 source slice: dig / harvest / assemble / trade. Not a production MMO server."):TEXT("Save rejected or actor spawn failed. Original save preserved; autosave disabled.");
    if(!CanSave)UE_LOG(LogTemp,Error,TEXT("%s"),*WorldStatus);
}
void ASkyWorld::RegisterPlayer(ASkyCharacter* P){
    if(!HasAuthority()||!P||P->Account)return;
    // Session slots, not authentication: do not expose this prototype to the public internet.
    int64 Candidate=1;for(TActorIterator<ASkyCharacter>I(GetWorld());I;++I)if(*I!=P)Candidate=FMath::Max(Candidate,(*I)->Account+1);
    P->Account=Candidate;
    if(!Model.state.players.count(Candidate)){
        Model.AddPlayer(Candidate,250);
        Model.Grant(Candidate,SkyCore::Item::Board,30);Model.Grant(Candidate,SkyCore::Item::Brick,40);
        Model.Grant(Candidate,SkyCore::Item::Nail,40);Model.Grant(Candidate,SkyCore::Item::Screw,40);
        Model.Grant(Candidate,SkyCore::Item::Fuel,10);
    }
    RefreshPlayers();
}
void ASkyWorld::RefreshPlayers(){
    for(TActorIterator<ASkyCharacter>I(GetWorld());I;++I){auto* P=*I;P->Coins=Model.Balance(P->Account);P->Inventory.Reset();
        for(int32 N=0;N<=11;++N){FSkyInventoryStack S;S.Item=N;S.Quantity=Model.Count(P->Account,static_cast<SkyCore::Item>(N));P->Inventory.Add(S);}P->ForceNetUpdate();}
    PublishOffers();
}
void ASkyWorld::PublishOffers(){Offers.Reset();for(const auto& Entry:Model.state.listings){const auto& L=Entry.second;if(L.closed||L.kind!=SkyCore::ListingKind::Items)continue;FSkyMarketOffer O;O.Id=L.id;O.Seller=L.seller;O.Item=(int32)L.item;O.Quantity=L.quantity;O.Price=L.price;Offers.Add(O);}ForceNetUpdate();}
void ASkyWorld::Notice(ASkyCharacter* P,const FString& Text){P->ClientNotice(Text);RefreshPlayers();}
void ASkyWorld::Trade(ASkyCharacter* P,bool bBuy,int64 Offer,int32 Item){
    if(!HasAuthority()||!P||P->Account<=0)return;
    if(bBuy){Notice(P,StatusText(Model.Purchase(P->Account,Offer)));return;}
    if(Item<0||Item>11)return;
    const auto Type=static_cast<SkyCore::Item>(Item);const int64 Qty=FMath::Min<int64>(5,Model.Count(P->Account,Type));
    if(Qty<=0){Notice(P,TEXT("No selected material in inventory."));return;}
    const int64 Id=NextId++;auto R=Model.PublishItems(P->Account,Id,Type,Qty,Qty*2);
    if(R){auto Purchase=Model.Purchase(Trader,Id);Notice(P,Purchase?TEXT("NPC bought your goods."):TEXT("Listed for other players; NPC has insufficient budget."));}else Notice(P,StatusText(R));
}
void ASkyWorld::Use(ASkyCharacter* P,ESkyTool Tool,const FHitResult& Hit,ESkyBuildKind Kind,FVector Size,FRotator Angles){
    if(!HasAuthority()||!P||P->Account<=0||FVector::Dist(P->GetActorLocation(),Hit.ImpactPoint)>800)return;
    if(Tool==ESkyTool::Build){
        if(Model.state.parts.size()>=1024){Notice(P,TEXT("Prototype part budget reached."));return;}
        FSkyPlacedPart S;S.Id=NextId++;S.Owner=P->Account;S.Kind=Kind;
        S.Size=Kind==ESkyBuildKind::Brick?FVector(25,12,6.5):Kind==ESkyBuildKind::Beam?FVector(Size.X,12,12):Size;
        const FRotator Rotation(Angles.Pitch,P->GetControlRotation().Yaw+Angles.Yaw,Angles.Roll);
        const FVector Normal=Hit.ImpactNormal;
        const FVector AxisX=Rotation.RotateVector(FVector::ForwardVector),AxisY=Rotation.RotateVector(FVector::RightVector),AxisZ=Rotation.RotateVector(FVector::UpVector);
        const float Extent=.5f*(FMath::Abs(FVector::DotProduct(Normal,AxisX))*S.Size.X+FMath::Abs(FVector::DotProduct(Normal,AxisY))*S.Size.Y+FMath::Abs(FVector::DotProduct(Normal,AxisZ))*S.Size.Z);
        const FVector Position=Hit.ImpactPoint+Normal*(Extent+.5f);
        const auto Material=Kind==ESkyBuildKind::Brick?SkyCore::Item::Brick:SkyCore::Item::Board;
        const auto R=Model.PlacePart(P->Account,S.Id,Material,{S.Size.X/100.,S.Size.Y/100.,S.Size.Z/100.},CorePoint(Position));
        if(!R){Notice(P,StatusText(R));return;}
        auto* Part=GetWorld()->SpawnActor<ASkyBuildPart>(Position,Rotation);if(!Part){Model.RemovePart(P->Account,S.Id);Notice(P,TEXT("Could not place actor; materials returned."));return;}Part->Configure(S);Notice(P,TEXT("Placed. Aim at a joint and use a hammer or screwdriver."));return;
    }
    if(auto* Island=Cast<ASkyIsland>(Hit.GetActor())){
        if(Tool!=ESkyTool::Shovel&&Tool!=ESkyTool::Pickaxe)return;
        const int32 Layer=Island->MaterialAtWorld(Hit.ImpactPoint-Hit.ImpactNormal*30);
        const bool Hard=Layer==1||Layer==3;
        if(Hard!=(Tool==ESkyTool::Pickaxe)){Notice(P,Hard?TEXT("Use the pickaxe on rock."):TEXT("Use the shovel on loose soil."));return;}
        const SkyCore::Item Item=Layer==3?SkyCore::Item::Ore:Layer==2?SkyCore::Item::Clay:Layer==1?SkyCore::Item::Stone:SkyCore::Item::Soil;
        if(Model.Count(P->Account,Item)>SkyCore::MaxQuantity-32)return;
        if(Island->Excavate(Hit.ImpactPoint-Hit.ImpactNormal*60,100)){
            const int64 Units=FMath::Clamp<int64>((int64)(Island->GetLastRemovedVolumeCm3()/100000),1,32);
            const int64 Deposit=NextId++;Model.SeedDeposit(Deposit,Item,Units);Model.Harvest(P->Account,Deposit,Hard?SkyCore::Tool::Pickaxe:SkyCore::Tool::Shovel,Units);
            Notice(P,TEXT("Excavated: newly removed material added to inventory."));
        }else Notice(P,TEXT("No new solid volume, or this island reached the excavation budget."));return;
    }
    if(auto* Resource=Cast<ASkyResource>(Hit.GetActor())){
        const bool IsWood=Resource->Resource==(int32)SkyCore::Item::Timber;
        if(Tool!=(IsWood?ESkyTool::Axe:ESkyTool::Pickaxe)){Notice(P,IsWood?TEXT("Use the axe on timber."):TEXT("Use the pickaxe on rock."));return;}
        const auto R=Model.Harvest(P->Account,Resource->Deposit,IsWood?SkyCore::Tool::Axe:SkyCore::Tool::Pickaxe,1);
        if(R&&--Resource->Remaining<=0)Resource->Destroy();Notice(P,StatusText(R));return;
    }
    if(auto* Part=Cast<ASkyBuildPart>(Hit.GetActor())){
        if(Tool==ESkyTool::Hammer||Tool==ESkyTool::Driver){
            if(Part->Spec.Owner!=P->Account){Part->TakeDamage(12,FDamageEvent(),P->GetController(),P);Notice(P,TEXT("Structure damaged."));return;}
            if(Part->Spec.Fasteners>=32){Notice(P,TEXT("Fastener limit for this part reached."));return;}
            const auto Fastener=Tool==ESkyTool::Hammer?SkyCore::Item::Nail:SkyCore::Item::Screw;
            if(Model.Count(P->Account,Fastener)<1){Notice(P,TEXT("Buy nails or screws first."));return;}
            // Find actual neighboring solid geometry close to the back of the chosen joint.
            FHitResult Support;FCollisionQueryParams Q(SCENE_QUERY_STAT(SkyJoint),false,P);Q.AddIgnoredActor(Part);
            const FVector From=Hit.ImpactPoint+Hit.ImpactNormal*2;
            const bool Found=GetWorld()->LineTraceSingleByChannel(Support,From,From-Hit.ImpactNormal*(Part->Spec.Size.GetMax()+30),ECC_Visibility,Q);
            auto* Other=Found?Cast<ASkyBuildPart>(Support.GetActor()):nullptr;
            if(!Found||(!Other&&!Cast<ASkyIsland>(Support.GetActor()))||FVector::Dist(From,Support.ImpactPoint)>Part->Spec.Size.GetMax()+20){Notice(P,TEXT("Aim where the board meets another part or the ground."));return;}
            if(++Part->Spec.Work<3){Part->ForceNetUpdate();Notice(P,TEXT("Working on the fastener..."));return;}
            auto R=Model.Fasten(P->Account,NextId++,Part->Spec.Id,Other?Other->Spec.Id:0,Fastener,CorePoint(Hit.ImpactPoint));
            Part->Spec.Work=0;
            if(R){++Part->Spec.Fasteners;Part->Spec.LocalFasteners.Add(Part->GetActorTransform().InverseTransformPosition(Hit.ImpactPoint));Part->OnRep_Spec();Part->ForceNetUpdate();}
            Notice(P,StatusText(R));return;
        }
        if(Tool==ESkyTool::Axe||Tool==ESkyTool::Pickaxe){Part->TakeDamage(20,FDamageEvent(),P->GetController(),P);Notice(P,TEXT("Structure damaged."));return;}
    }
    if(auto* Target=Cast<ASkyCharacter>(Hit.GetActor()))if(Target!=P&&(Tool==ESkyTool::Axe||Tool==ESkyTool::Pickaxe))Target->TakeDamage(20,FDamageEvent(),P->GetController(),P);
}
void ASkyWorld::SaveWorld(){
    if(!HasAuthority()||Loading||!CanSave)return;
    auto Root=MakeShared<FJsonObject>();Root->SetNumberField("schema",1);Root->SetNumberField("next_id",NextId);
    std::ostringstream Core;if(!Model.Serialize(Core)){UE_LOG(LogTemp,Error,TEXT("Invalid model: save aborted; previous slot preserved."));return;}Root->SetStringField("core",UTF8_TO_TCHAR(Core.str().c_str()));
    TArray<TSharedPtr<FJsonValue>> PartArray;
    for(TActorIterator<ASkyBuildPart>I(GetWorld());I;++I){
        const auto* P=*I;if(P->Spec.Id<=0||!Model.state.parts.count(P->Spec.Id))continue;
        auto O=VectorJson(P->GetActorLocation());O->SetNumberField("id",P->Spec.Id);O->SetNumberField("kind",(int32)P->Spec.Kind);O->SetNumberField("owner",P->Spec.Owner);
        O->SetObjectField("rotation",VectorJson(P->GetActorRotation().Euler()));O->SetObjectField("size",VectorJson(P->Spec.Size));
        O->SetNumberField("health",P->Spec.Health);O->SetNumberField("fasteners",P->Spec.Fasteners);
        TArray<TSharedPtr<FJsonValue>> Fasteners;for(const auto& V:P->Spec.LocalFasteners)Fasteners.Add(MakeShared<FJsonValueObject>(VectorJson(V)));
        O->SetArrayField("joints",Fasteners);PartArray.Add(MakeShared<FJsonValueObject>(O));
    }
    Root->SetArrayField("parts",PartArray);
    TArray<TSharedPtr<FJsonValue>> IslandArray;
    for(const ASkyIsland* I:Islands){if(!I)continue;auto O=VectorJson(I->GetActorLocation());O->SetNumberField("seed",I->IslandSeed);O->SetNumberField("radius",I->IslandRadius);
        TArray<TSharedPtr<FJsonValue>> Stamps;for(const auto& S:I->DigStamps){auto V=VectorJson(S.Center);V->SetNumberField("radius",S.Radius);Stamps.Add(MakeShared<FJsonValueObject>(V));}
        O->SetArrayField("stamps",Stamps);IslandArray.Add(MakeShared<FJsonValueObject>(O));
    }
    Root->SetArrayField("islands",IslandArray);
    FString Payload;auto Writer=TJsonWriterFactory<>::Create(&Payload);FJsonSerializer::Serialize(Root,Writer);
    auto* Save=Cast<USkySave>(UGameplayStatics::CreateSaveGameObject(USkySave::StaticClass()));Save->Payload=Payload;
    if(!UGameplayStatics::SaveGameToSlot(Save,TEXT("SkyWorld_v1"),0))UE_LOG(LogTemp,Error,TEXT("Sky world save failed."));
}
void ASkyWorld::RestoreWorld(){
    if(!UGameplayStatics::DoesSaveGameExist(TEXT("SkyWorld_v1"),0))return;
    CanSave=false; // Any rejection preserves the original slot; no autosave overwrite.
    auto* Save=Cast<USkySave>(UGameplayStatics::LoadGameFromSlot(TEXT("SkyWorld_v1"),0));if(!Save||Save->Payload.Len()>24*1024*1024)return;
    TSharedPtr<FJsonObject> Root;auto Reader=TJsonReaderFactory<>::Create(Save->Payload);
    if(!FJsonSerializer::Deserialize(Reader,Root)||!Root.IsValid())return;
    double Schema=0,Next=0;FString Core;
    const TArray<TSharedPtr<FJsonValue>>* Parts=nullptr;const TArray<TSharedPtr<FJsonValue>>* SavedIslands=nullptr;
    if(!Root->TryGetNumberField(TEXT("schema"),Schema)||Schema!=1||!Root->TryGetNumberField(TEXT("next_id"),Next)||!FMath::IsFinite(Next)||Next<10000||Next>1000000000||FMath::FloorToDouble(Next)!=Next||!Root->TryGetStringField(TEXT("core"),Core)||!Root->TryGetArrayField(TEXT("parts"),Parts)||Parts->Num()>1024||!Root->TryGetArrayField(TEXT("islands"),SavedIslands)||SavedIslands->Num()!=3)return;
    SkyCore::Model Candidate;std::istringstream Stream(TCHAR_TO_UTF8(*Core));if(!Candidate.Deserialize(Stream))return;
    int64 MaxId=9999;
    auto FindMax=[&](const auto& Map){for(const auto& Entry:Map)MaxId=FMath::Max<int64>(MaxId,(int64)Entry.first);};
    FindMax(Candidate.state.deposits);FindMax(Candidate.state.parts);FindMax(Candidate.state.fasteners);FindMax(Candidate.state.houses);FindMax(Candidate.state.listings);FindMax(Candidate.state.factories);
    if(Next<=MaxId||Parts->Num()!=(int32)Candidate.state.parts.size())return;
    TSet<int64> SeenParts;
    struct FPendingPart{FSkyPlacedPart Spec;FVector Position;FRotator Rotation;};TArray<FPendingPart> Pending;
    for(const auto& Value:*Parts){
        auto O=Value->AsObject();if(!O.IsValid()||!O->HasTypedField<EJson::Number>(TEXT("id"))||!O->HasTypedField<EJson::Number>(TEXT("kind"))||!O->HasTypedField<EJson::Number>(TEXT("health"))||!O->HasTypedField<EJson::Object>(TEXT("rotation"))||!O->HasTypedField<EJson::Object>(TEXT("size")))return;
        const double RawId=O->GetNumberField("id");if(!FMath::IsFinite(RawId)||RawId<=0||RawId>=1000000000||FMath::FloorToDouble(RawId)!=RawId)return;
        FPendingPart A;A.Spec.Id=(int64)RawId;if(!Candidate.state.parts.count(A.Spec.Id)||SeenParts.Contains(A.Spec.Id))return;SeenParts.Add(A.Spec.Id);
        const auto& Stored=Candidate.state.parts.at(A.Spec.Id);A.Spec.Owner=Stored.owner;
        const double RawKind=O->GetNumberField("kind");if(!FMath::IsFinite(RawKind)||RawKind<0||RawKind>2||FMath::FloorToDouble(RawKind)!=RawKind)return;const int32 Kind=(int32)RawKind;A.Spec.Kind=static_cast<ESkyBuildKind>(Kind);
        A.Position=FVector(Stored.position.x,Stored.position.y,Stored.position.z)*100;
        A.Spec.Size=FVector(Stored.dimensions.length,Stored.dimensions.width,Stored.dimensions.height)*100;
        A.Rotation=FRotator::MakeFromEuler(ReadVector(O->GetObjectField("rotation")));A.Spec.Health=O->GetNumberField("health");
        if(A.Rotation.ContainsNaN()||!FMath::IsFinite(A.Spec.Health)||A.Spec.Health<=0||A.Spec.Health>100)return;
        for(const auto& Joint:Candidate.state.fasteners)if(Joint.second.partA==A.Spec.Id){const auto V=Joint.second.position;A.Spec.LocalFasteners.Add(FTransform(A.Rotation,A.Position).InverseTransformPosition(FVector(V.x,V.y,V.z)*100));}
        A.Spec.Fasteners=A.Spec.LocalFasteners.Num();if(A.Spec.Fasteners>32)return;Pending.Add(A);
    }
    struct FPendingIsland{FVector Position;int32 Seed;float Radius;TArray<FSkyDigStamp> Stamps;};TArray<FPendingIsland> Terrain;
    for(const auto& Value:*SavedIslands){
        auto O=Value->AsObject();if(!O.IsValid()||!O->HasTypedField<EJson::Number>(TEXT("seed"))||!O->HasTypedField<EJson::Number>(TEXT("radius")))return;
        const TArray<TSharedPtr<FJsonValue>>* Stamps=nullptr;if(!O->TryGetArrayField(TEXT("stamps"),Stamps)||Stamps->Num()>128)return;
        FPendingIsland A;A.Position=ReadVector(O);const double RawSeed=O->GetNumberField("seed");if(!FMath::IsFinite(RawSeed)||RawSeed<0||RawSeed>1000000||FMath::FloorToDouble(RawSeed)!=RawSeed)return;A.Seed=(int32)RawSeed;A.Radius=O->GetNumberField("radius");if(A.Position.ContainsNaN()||A.Position.GetAbsMax()>1000000||!FMath::IsFinite(A.Radius)||A.Radius<1000||A.Radius>4000)return;
        for(const auto& V:*Stamps){auto S=V->AsObject();if(!S.IsValid()||!S->HasTypedField<EJson::Number>(TEXT("radius")))return;FSkyDigStamp Stamp;Stamp.Center=ReadVector(S);Stamp.Radius=S->GetNumberField("radius");if(Stamp.Center.ContainsNaN()||!FMath::IsFinite(Stamp.Radius)||Stamp.Radius<80||Stamp.Radius>260)return;if(!SkyTerrain::Field(A.Seed,A.Radius).ValidStamp({{Stamp.Center.X,Stamp.Center.Y,Stamp.Center.Z},Stamp.Radius}))return;A.Stamps.Add(Stamp);}Terrain.Add(A);
    }
    Loading=true;
    TArray<AActor*> Spawned;
    auto Abort=[&](){for(AActor* Actor:Spawned)if(Actor)Actor->Destroy();Islands.Reset();Loading=false;};
    for(const auto& A:Terrain){auto* I=GetWorld()->SpawnActor<ASkyIsland>(A.Position,FRotator::ZeroRotator);if(!I){Abort();return;}Spawned.Add(I);I->Initialize(A.Seed,A.Radius);if(!I->RestoreStamps(A.Stamps)){Abort();return;}Islands.Add(I);}
    for(const auto& A:Pending){auto* P=GetWorld()->SpawnActor<ASkyBuildPart>(A.Position,A.Rotation);if(!P){Abort();return;}Spawned.Add(P);P->Configure(A.Spec);}
    Model=MoveTemp(Candidate);NextId=(int64)Next;CanSave=true;Loading=false;
}
void ASkyWorld::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& Out)const{Super::GetLifetimeReplicatedProps(Out);DOREPLIFETIME(ASkyWorld,Offers);DOREPLIFETIME(ASkyWorld,WorldStatus);}
