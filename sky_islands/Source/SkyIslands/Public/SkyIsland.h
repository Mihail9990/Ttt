#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "SkyIsland.generated.h"

class UProceduralMeshComponent;

USTRUCT(BlueprintType)
struct FSkyDigStamp
{
    GENERATED_BODY()
    // Stored in island-local centimetres, so digging follows a moving island.
    UPROPERTY(EditAnywhere, BlueprintReadWrite) FVector Center = FVector::ZeroVector;
    UPROPERTY(EditAnywhere, BlueprintReadWrite) float Radius = 180.f;
};

/** Smooth, volumetric island; only authoritative server operations change terrain. */
UCLASS()
class SKYISLANDS_API ASkyIsland : public AActor
{
    GENERATED_BODY()
public:
    ASkyIsland();
    virtual void BeginPlay() override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

    void Initialize(int32 InSeed, float InRadius);
    bool Excavate(FVector WorldHit, float DigRadius);
    float DensityAtWorld(FVector WorldPoint) const;
    int32 MaterialAtWorld(FVector WorldPoint) const;
    double GetLastRemovedVolumeCm3() const { return LastRemovedVolumeCm3; }
    bool RestoreStamps(const TArray<FSkyDigStamp>& SavedStamps);

    UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<UProceduralMeshComponent> Terrain;
    UPROPERTY(ReplicatedUsing=OnRep_Terrain, VisibleAnywhere, BlueprintReadOnly) int32 IslandSeed = 41;
    UPROPERTY(ReplicatedUsing=OnRep_Terrain, VisibleAnywhere, BlueprintReadOnly) float IslandRadius = 2400.f;
    UPROPERTY(ReplicatedUsing=OnRep_Terrain, VisibleAnywhere, BlueprintReadOnly) TArray<FSkyDigStamp> DigStamps;
private:
    UFUNCTION() void OnRep_Terrain();
    void RebuildMesh();
    double LastRemovedVolumeCm3 = 0;
};
