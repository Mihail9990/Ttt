#pragma once
#include "CoreMinimal.h"
#include "GameFramework/SaveGame.h"
#include "SkySave.generated.h"
UCLASS()
class SKYISLANDS_API USkySave : public USaveGame {
    GENERATED_BODY()
public:
    UPROPERTY() FString Payload;
};
