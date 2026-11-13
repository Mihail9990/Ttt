#pragma once
#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "SkyHUD.generated.h"
UCLASS()
class SKYISLANDS_API ASkyHUD : public AHUD {
    GENERATED_BODY()
public:
    virtual void DrawHUD() override;
    bool HandleTouch(FVector2D Position);
};
