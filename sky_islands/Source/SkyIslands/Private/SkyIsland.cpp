#include "SkyIsland.h"
#include "ProceduralMeshComponent.h"
#include "Materials/MaterialInterface.h"
#include "Net/UnrealNetwork.h"
#include "Core/IslandField.h"

namespace
{
SkyTerrain::Vec3 V(const FVector& P) { return {P.X, P.Y, P.Z}; }
FVector V(const SkyTerrain::Vec3& P) { return FVector(P.x, P.y, P.z); }
SkyTerrain::Field MakeField(const ASkyIsland& Island)
{
    SkyTerrain::Field Field(Island.IslandSeed, Island.IslandRadius);
    for (const FSkyDigStamp& Stamp : Island.DigStamps)
    {
        const SkyTerrain::Stamp S{V(Stamp.Center), Stamp.Radius};
        if (Field.ValidStamp(S) && Field.stamps.size() < SkyTerrain::Field::MaxStamps)
            Field.stamps.push_back(S);
    }
    return Field;
}
}

ASkyIsland::ASkyIsland()
{
    bReplicates = true;
    bAlwaysRelevant = true; // Starter archipelago only; replace with spatial relevance at world scale.
    SetReplicateMovement(true);
    NetUpdateFrequency = 3.f;
    Terrain = CreateDefaultSubobject<UProceduralMeshComponent>(TEXT("Terrain"));
    SetRootComponent(Terrain);
    Terrain->bUseAsyncCooking = true;
    Terrain->bUseComplexAsSimpleCollision = true;
    Terrain->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
    Terrain->SetCollisionObjectType(ECC_WorldStatic);
    Terrain->SetCollisionResponseToAllChannels(ECR_Block);
    Terrain->SetGenerateOverlapEvents(false);
}

void ASkyIsland::BeginPlay()
{
    Super::BeginPlay();
    RebuildMesh();
}

void ASkyIsland::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(ASkyIsland, IslandSeed);
    DOREPLIFETIME(ASkyIsland, IslandRadius);
    DOREPLIFETIME(ASkyIsland, DigStamps);
}

void ASkyIsland::Initialize(int32 InSeed, float InRadius)
{
    if (!HasAuthority() || !FMath::IsFinite(InRadius)) return;
    IslandSeed = InSeed;
    IslandRadius = FMath::Clamp(InRadius, 500.f, 6000.f);
    DigStamps.Reset();
    RebuildMesh();
    ForceNetUpdate();
}

float ASkyIsland::DensityAtWorld(FVector WorldPoint) const
{
    const auto Field = MakeField(*this);
    const double Scale = FMath::Max(0.01, GetActorScale3D().GetAbsMax());
    return static_cast<float>(Field.Density(V(GetActorTransform().InverseTransformPosition(WorldPoint))) * Scale);
}

int32 ASkyIsland::MaterialAtWorld(FVector WorldPoint) const
{
    return MakeField(*this).Material(V(GetActorTransform().InverseTransformPosition(WorldPoint)));
}

bool ASkyIsland::Excavate(FVector WorldHit, float DigRadius)
{
    LastRemovedVolumeCm3 = 0;
    if (!HasAuthority() || !FMath::IsFinite(DigRadius) || WorldHit.ContainsNaN()) return false;
    auto Field = MakeField(*this);
    const double Scale = FMath::Max(0.01, GetActorScale3D().GetAbsMax());
    const SkyTerrain::Stamp Stamp{V(GetActorTransform().InverseTransformPosition(WorldHit)), DigRadius / Scale};
    const double RemovedLocal = Field.Excavate(Stamp);
    if (RemovedLocal <= 0) return false;
    FSkyDigStamp Saved;
    Saved.Center = V(Stamp.center);
    Saved.Radius = static_cast<float>(Stamp.radius);
    DigStamps.Add(Saved);
    LastRemovedVolumeCm3 = RemovedLocal * Scale * Scale * Scale;
    // Geometry collision cooking may finish later; density changes immediately on the server.
    // Gameplay must award resources only when this function returns true.
    RebuildMesh();
    ForceNetUpdate();
    return true;
}

bool ASkyIsland::RestoreStamps(const TArray<FSkyDigStamp>& SavedStamps)
{
    if (!HasAuthority() || SavedStamps.Num() > static_cast<int32>(SkyTerrain::Field::MaxStamps)) return false;
    SkyTerrain::Field Field(IslandSeed, IslandRadius);
    for (const auto& Stamp : SavedStamps)
        if (!Field.ValidStamp({V(Stamp.Center), Stamp.Radius})) return false;
    DigStamps = SavedStamps;
    RebuildMesh();
    ForceNetUpdate();
    return true;
}

void ASkyIsland::OnRep_Terrain()
{
    RebuildMesh();
}

void ASkyIsland::RebuildMesh()
{
    const auto Field = MakeField(*this);
    const auto Triangles = Field.Mesh(150);
    Terrain->ClearAllMeshSections();
    for (int32 Section = 0; Section < 2; ++Section)
    {
        TArray<FVector> Vertices, Normals;
        TArray<int32> Indices;
        TArray<FVector2D> UVs;
        TArray<FLinearColor> Colors;
        TArray<FProcMeshTangent> Tangents;
        for (const auto& Triangle : Triangles)
        {
            if (Triangle.material != Section) continue;
            for (const auto& Vertex : Triangle.vertices)
            {
                Indices.Add(Vertices.Num());
                Vertices.Add(V(Vertex.position));
                const FVector Normal = V(Vertex.normal);
                Normals.Add(Normal);
                const auto& P = Vertex.position;
                // World-scale UVs; 1 tile per metre, with side projection for cliffs/caves.
                if (Section == 0 || FMath::Abs(Normal.Z) > .65f) UVs.Add(FVector2D(P.x / 100., P.y / 100.));
                else if (FMath::Abs(Normal.X) > FMath::Abs(Normal.Y)) UVs.Add(FVector2D(P.y / 100., -P.z / 100.));
                else UVs.Add(FVector2D(P.x / 100., -P.z / 100.));
                Colors.Add(Section == 0 ? FLinearColor(.24f,.32f,.12f,1) : FLinearColor(.32f,.28f,.23f,1));
            }
        }
        if (Vertices.IsEmpty()) continue;
        Terrain->CreateMeshSection_LinearColor(Section, Vertices, Indices, Normals, UVs, Colors, Tangents, true, false);
        const TCHAR* MaterialPath = Section == 0 ? TEXT("/Game/Art/Materials/M_Ground.M_Ground") : TEXT("/Game/Art/Materials/M_Rock.M_Rock");
        if (UMaterialInterface* Material = LoadObject<UMaterialInterface>(nullptr, MaterialPath)) Terrain->SetMaterial(Section, Material);
    }
}
