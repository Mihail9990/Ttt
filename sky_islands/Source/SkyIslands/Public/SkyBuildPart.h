#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "SkyTypes.h"
#include "SkyBuildPart.generated.h"
class UStaticMeshComponent;
UCLASS()
class SKYISLANDS_API ASkyBuildPart : public AActor {
    GENERATED_BODY()
public:
    ASkyBuildPart();
    UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> Body;
    UPROPERTY(ReplicatedUsing=OnRep_Spec) FSkyPlacedPart Spec;
    UFUNCTION() void OnRep_Spec();
    void Configure(const FSkyPlacedPart& NewSpec);
    virtual float TakeDamage(float Amount, const FDamageEvent& Event, AController* InstigatorController, AActor* Causer) override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& Out) const override;
private:
    UPROPERTY() TArray<TObjectPtr<UStaticMeshComponent>> Connectors;
};
