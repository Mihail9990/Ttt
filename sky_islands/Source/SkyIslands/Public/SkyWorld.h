#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "SkyTypes.h"
#include "Core/WorldModel.h"
#include "SkyWorld.generated.h"
class ASkyCharacter;
class ASkyIsland;
class ASkyBuildPart;
UCLASS()
class SKYISLANDS_API ASkyResource : public AActor {
    GENERATED_BODY()
public:
    ASkyResource();
    UPROPERTY(VisibleAnywhere) TObjectPtr<class UStaticMeshComponent> Mesh;
    UPROPERTY(Replicated) int64 Deposit=0;
    UPROPERTY(Replicated) int32 Resource=0;
    UPROPERTY(Replicated) int32 Remaining=12;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& Out) const override;
};
UCLASS()
class SKYISLANDS_API ASkyWorld : public AActor {
    GENERATED_BODY()
public:
    ASkyWorld();
    virtual void BeginPlay() override;
    virtual void Tick(float Delta) override;
    virtual void EndPlay(const EEndPlayReason::Type Reason) override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& Out) const override;
    SkyCore::Model Model;
    UPROPERTY(Replicated) TArray<FSkyMarketOffer> Offers;
    UPROPERTY(Replicated) FString WorldStatus;
    void RegisterPlayer(ASkyCharacter* Player);
    void RefreshPlayers();
    void Use(ASkyCharacter* Player,ESkyTool Tool,const FHitResult& Hit,ESkyBuildKind Kind,FVector Size,FRotator Angles);
    void Trade(ASkyCharacter* Player,bool Buy,int64 Offer,int32 Item);
    void SaveWorld();
    static ASkyWorld* Find(UWorld* World);
private:
    int64 NextId=10000;
    float SaveClock=0;
    bool Loading=false;
    bool CanSave=true;
    UPROPERTY() TArray<TObjectPtr<ASkyIsland>> Islands;
    void SeedScene();
    void RestoreWorld();
    void PublishOffers();
    void Notice(ASkyCharacter* Player,const FString& Text);
};
