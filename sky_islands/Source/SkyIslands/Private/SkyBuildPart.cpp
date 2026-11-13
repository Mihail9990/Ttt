#include "SkyBuildPart.h"
#include "Engine/World.h"
#include "Engine/StaticMesh.h"
#include "Engine/DamageEvents.h"
#include "SkyWorld.h"
#include "Components/StaticMeshComponent.h"
#include "Components/SceneComponent.h"
#include "Materials/MaterialInterface.h"
#include "Net/UnrealNetwork.h"
#include "UObject/ConstructorHelpers.h"

ASkyBuildPart::ASkyBuildPart() {
    bReplicates=true; SetReplicateMovement(true);
    RootComponent=CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
    Body=CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Part"));
    Body->SetupAttachment(RootComponent);
    static ConstructorHelpers::FObjectFinder<UStaticMesh> Cube(TEXT("/Engine/BasicShapes/Cube.Cube"));
    Body->SetStaticMesh(Cube.Object);
    Body->SetCollisionProfileName(TEXT("BlockAll"));
}
void ASkyBuildPart::Configure(const FSkyPlacedPart& NewSpec) {Spec=NewSpec;OnRep_Spec();ForceNetUpdate();}
void ASkyBuildPart::OnRep_Spec() {
    Body->SetRelativeScale3D(Spec.Size/100.f);
    const TCHAR* Path=Spec.Kind==ESkyBuildKind::Brick ? TEXT("/Game/Art/Materials/M_Brick.M_Brick") : TEXT("/Game/Art/Materials/M_Wood.M_Wood");
    if(auto* Material=LoadObject<UMaterialInterface>(nullptr,Path)) Body->SetMaterial(0,Material);
    for(UStaticMeshComponent* C:Connectors) if(C) C->DestroyComponent();
    Connectors.Reset();
    auto* Cylinder=LoadObject<UStaticMesh>(nullptr,TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
    for(const FVector& Point:Spec.LocalFasteners) {
        auto* C=NewObject<UStaticMeshComponent>(this);
        C->SetupAttachment(RootComponent);C->SetStaticMesh(Cylinder);
        C->SetRelativeLocation(Point);C->SetRelativeScale3D(FVector(.012f,.012f,.008f));
        C->SetCollisionEnabled(ECollisionEnabled::NoCollision);
        if(auto* Metal=LoadObject<UMaterialInterface>(nullptr,TEXT("/Game/Art/Materials/M_Metal.M_Metal"))) C->SetMaterial(0,Metal);
        C->RegisterComponent();Connectors.Add(C);
    }
}
float ASkyBuildPart::TakeDamage(float Amount,const FDamageEvent&,AController*,AActor*) {
    if(!HasAuthority()||!FMath::IsFinite(Amount)||Amount<=0) return 0;
    const float Applied=Amount / (1.f+FMath::Min(Spec.Fasteners,16)*.15f);
    Spec.Health=FMath::Max(0.f,Spec.Health-Applied);ForceNetUpdate();
    if(Spec.Health<=0){if(auto* W=ASkyWorld::Find(GetWorld()))W->Model.DestroyPart(Spec.Id);Destroy();}
    return Applied;
}
void ASkyBuildPart::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& Out) const {
    Super::GetLifetimeReplicatedProps(Out);DOREPLIFETIME(ASkyBuildPart,Spec);
}
