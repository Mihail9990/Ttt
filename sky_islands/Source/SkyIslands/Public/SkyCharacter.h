#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "SkyTypes.h"
#include "SkyCharacter.generated.h"
class UCameraComponent;
class UStaticMeshComponent;
UCLASS()
class SKYISLANDS_API ASkyCharacter : public ACharacter {
    GENERATED_BODY()
public:
    ASkyCharacter();
    virtual void BeginPlay() override;
    virtual void Tick(float Delta) override;
    virtual void SetupPlayerInputComponent(UInputComponent* Input) override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& Out) const override;
    virtual float TakeDamage(float Amount,const FDamageEvent& Event,AController* InstigatorController,AActor* Causer) override;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UCameraComponent> Camera;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> HeldTool;
    UPROPERTY(Replicated) int64 Account=0;
    UPROPERTY(Replicated) float Health=100;
    UPROPERTY(Replicated) int64 Coins=0;
    UPROPERTY(Replicated) TArray<FSkyInventoryStack> Inventory;
    UPROPERTY() ESkyTool Tool=ESkyTool::Shovel;
    UPROPERTY() ESkyBuildKind BuildKind=ESkyBuildKind::Board;
    UPROPERTY() FString Notice;
    bool MarketOpen=false;
    float BoardLength=200;
    float PlacementYaw=0;
    float PlacementPitch=0, PlacementRoll=0;
    float BoardWidth=20, BoardHeight=3;
    int32 MarketSelection=0;
    void Primary(); void Secondary(); void NextTool(); void PreviousTool(); void Rotate();
    void Buy(); void Sell(); void ToggleMarket(); void Save();
    void SetTool(int32 Index);
    int64 Count(int32 Item) const;
    UFUNCTION(Server,Reliable) void ServerUse(uint8 ToolId,uint8 Kind,FVector Size,FRotator Angles);
    UFUNCTION(Server,Reliable) void ServerTrade(bool bBuy,int64 Offer,int32 Item);
    UFUNCTION(Server,Reliable) void ServerSave();
    UFUNCTION(Client,Reliable) void ClientNotice(const FString& Message);
private:
    double LastCommand=-1;
    float ToolKick=0;
    int32 MoveTouch=INDEX_NONE, LookTouch=INDEX_NONE;
    FVector2D TouchOrigin,LastLook,TouchMove;
    void Forward(float Value); void Right(float Value); void Turn(float Value); void Look(float Value);
    void TouchBegin(ETouchIndex::Type Finger,FVector Position);
    void TouchMoveEvent(ETouchIndex::Type Finger,FVector Position);
    void TouchEnd(ETouchIndex::Type Finger,FVector Position);
    void Tool1();void Tool2();void Tool3();void Tool4();void Tool5();void Tool6();
    void Longer(); void Shorter();
    void PitchPart();void RollPart();void Wider();void Narrower();void Thicker();void Thinner();
};
