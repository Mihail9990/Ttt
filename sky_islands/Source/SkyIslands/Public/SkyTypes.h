#pragma once
#include "CoreMinimal.h"
#include "SkyTypes.generated.h"

UENUM(BlueprintType)
enum class ESkyTool : uint8 { Shovel, Axe, Pickaxe, Hammer, Driver, Build };
UENUM(BlueprintType)
enum class ESkyBuildKind : uint8 { Board, Brick, Beam, Turret, Drone, Guard };

USTRUCT(BlueprintType)
struct FSkyPlacedPart {
    GENERATED_BODY()
    UPROPERTY() int64 Id=0;
    UPROPERTY() int64 Owner=0;
    UPROPERTY() ESkyBuildKind Kind=ESkyBuildKind::Board;
    UPROPERTY() FVector Size=FVector(200,20,4);
    UPROPERTY() int32 Fasteners=0;
    UPROPERTY() int32 Work=0;
    UPROPERTY() TArray<FVector> LocalFasteners;
    UPROPERTY() float Health=100;
};
USTRUCT()
struct FSkyInventoryStack {
    GENERATED_BODY()
    UPROPERTY() int32 Item=0;
    UPROPERTY() int64 Quantity=0;
};
USTRUCT()
struct FSkyMarketOffer {
    GENERATED_BODY()
    UPROPERTY() int64 Id=0;
    UPROPERTY() int64 Seller=0;
    UPROPERTY() int32 Item=0;
    UPROPERTY() int64 Quantity=0;
    UPROPERTY() int64 Price=0;
};
