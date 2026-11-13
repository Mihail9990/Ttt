#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "SkyGameMode.generated.h"
UCLASS()
class SKYISLANDS_API ASkyGameMode : public AGameModeBase {
    GENERATED_BODY()
public:
    ASkyGameMode();
    virtual void InitGame(const FString& Map,const FString& Options,FString& Error) override;
};
