#include "SkyCharacter.h"
#include "Engine/World.h"
#include "Engine/StaticMesh.h"
#include "Engine/DamageEvents.h"
#include "SkyWorld.h"
#include "SkyHUD.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/InputComponent.h"
#include "Components/StaticMeshComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "Net/UnrealNetwork.h"
#include "Kismet/GameplayStatics.h"
#include "Materials/MaterialInterface.h"

ASkyCharacter::ASkyCharacter() {
    PrimaryActorTick.bCanEverTick=true;
    bReplicates=true;
    auto* Avatar=CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Avatar"));
    Avatar->SetupAttachment(GetCapsuleComponent());
    Avatar->SetStaticMesh(LoadObject<UStaticMesh>(nullptr,TEXT("/Engine/BasicShapes/Cylinder.Cylinder")));
    Avatar->SetRelativeScale3D(FVector(.65,.65,1.7));Avatar->SetOwnerNoSee(true);
    Avatar->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    GetCapsuleComponent()->InitCapsuleSize(34,88);
    Camera=CreateDefaultSubobject<UCameraComponent>(TEXT("View"));
    Camera->SetupAttachment(GetCapsuleComponent());Camera->SetRelativeLocation(FVector(0,0,64));
    Camera->bUsePawnControlRotation=true;
    HeldTool=CreateDefaultSubobject<UStaticMeshComponent>(TEXT("HeldTool"));
    HeldTool->SetupAttachment(Camera);HeldTool->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    HeldTool->SetOnlyOwnerSee(true);HeldTool->CastShadow=false;
    GetCharacterMovement()->MaxWalkSpeed=420;
    GetCharacterMovement()->JumpZVelocity=490;
}
void ASkyCharacter::BeginPlay(){Super::BeginPlay();SetTool(0);}
void ASkyCharacter::Tick(float Delta){
    Super::Tick(Delta);
    if(HasAuthority() && Account==0) if(auto* W=ASkyWorld::Find(GetWorld())) W->RegisterPlayer(this);
    if(HasAuthority()&&GetActorLocation().Z < -6500){SetActorLocation(FVector(-800,0,450));GetCharacterMovement()->StopMovementImmediately();Health=FMath::Max(20.f,Health-20);}
    if(IsLocallyControlled()) {
        Forward(TouchMove.Y);Right(TouchMove.X);
        ToolKick=FMath::FInterpTo(ToolKick,0,Delta,12);
        HeldTool->SetRelativeRotation(FRotator(-12-ToolKick*25,2,0));
    }
}
void ASkyCharacter::Forward(float V){if(!MarketOpen)AddMovementInput(GetActorForwardVector(),V);}
void ASkyCharacter::Right(float V){if(!MarketOpen)AddMovementInput(GetActorRightVector(),V);}
void ASkyCharacter::Turn(float V){if(!MarketOpen)AddControllerYawInput(V);}
void ASkyCharacter::Look(float V){if(!MarketOpen)AddControllerPitchInput(V);}
void ASkyCharacter::SetupPlayerInputComponent(UInputComponent* I){
    Super::SetupPlayerInputComponent(I);
    I->BindAxis("MoveForward",this,&ASkyCharacter::Forward);I->BindAxis("MoveRight",this,&ASkyCharacter::Right);
    I->BindAxis("Turn",this,&ASkyCharacter::Turn);I->BindAxis("LookUp",this,&ASkyCharacter::Look);
    I->BindAction("Jump",IE_Pressed,this,&ACharacter::Jump);I->BindAction("Jump",IE_Released,this,&ACharacter::StopJumping);
    I->BindAction("Primary",IE_Pressed,this,&ASkyCharacter::Primary);I->BindAction("Secondary",IE_Pressed,this,&ASkyCharacter::Secondary);
    I->BindAction("NextTool",IE_Pressed,this,&ASkyCharacter::NextTool);I->BindAction("PreviousTool",IE_Pressed,this,&ASkyCharacter::PreviousTool);
    I->BindAction("Rotate",IE_Pressed,this,&ASkyCharacter::Rotate);I->BindAction("Market",IE_Pressed,this,&ASkyCharacter::ToggleMarket);
    I->BindAction("Save",IE_Pressed,this,&ASkyCharacter::Save);I->BindAction("Buy",IE_Pressed,this,&ASkyCharacter::Buy);I->BindAction("Sell",IE_Pressed,this,&ASkyCharacter::Sell);
    I->BindAction("LengthUp",IE_Pressed,this,&ASkyCharacter::Longer);I->BindAction("LengthDown",IE_Pressed,this,&ASkyCharacter::Shorter);
    I->BindAction("Tool1",IE_Pressed,this,&ASkyCharacter::Tool1);I->BindAction("Tool2",IE_Pressed,this,&ASkyCharacter::Tool2);
    I->BindAction("Tool3",IE_Pressed,this,&ASkyCharacter::Tool3);I->BindAction("Tool4",IE_Pressed,this,&ASkyCharacter::Tool4);
    I->BindAction("Tool5",IE_Pressed,this,&ASkyCharacter::Tool5);I->BindAction("Tool6",IE_Pressed,this,&ASkyCharacter::Tool6);
    I->BindAction("PitchPart",IE_Pressed,this,&ASkyCharacter::PitchPart);I->BindAction("RollPart",IE_Pressed,this,&ASkyCharacter::RollPart);
    I->BindAction("WidthUp",IE_Pressed,this,&ASkyCharacter::Wider);I->BindAction("WidthDown",IE_Pressed,this,&ASkyCharacter::Narrower);
    I->BindAction("HeightUp",IE_Pressed,this,&ASkyCharacter::Thicker);I->BindAction("HeightDown",IE_Pressed,this,&ASkyCharacter::Thinner);
    I->BindTouch(IE_Pressed,this,&ASkyCharacter::TouchBegin);I->BindTouch(IE_Repeat,this,&ASkyCharacter::TouchMoveEvent);I->BindTouch(IE_Released,this,&ASkyCharacter::TouchEnd);
}
void ASkyCharacter::SetTool(int32 Index){
    Tool=static_cast<ESkyTool>((Index+6)%6);
    const TCHAR* Asset=Tool==ESkyTool::Driver ? TEXT("/Game/Art/Tools/SM_Drill.SM_Drill") : Tool==ESkyTool::Hammer?TEXT("/Game/Art/Tools/SM_Hammer.SM_Hammer"):nullptr;
    UStaticMesh* M=Asset?LoadObject<UStaticMesh>(nullptr,Asset):nullptr;
    HeldTool->SetStaticMesh(M);HeldTool->SetRelativeLocation(FVector(42,20,-24));HeldTool->SetRelativeScale3D(FVector(.6));
}
void ASkyCharacter::NextTool(){if(MarketOpen){++MarketSelection;return;}SetTool(static_cast<int32>(Tool)+1);}
void ASkyCharacter::PreviousTool(){if(MarketOpen){MarketSelection=FMath::Max(0,MarketSelection-1);return;}SetTool(static_cast<int32>(Tool)-1);}
void ASkyCharacter::Tool1(){SetTool(0);}void ASkyCharacter::Tool2(){SetTool(1);}void ASkyCharacter::Tool3(){SetTool(2);}void ASkyCharacter::Tool4(){SetTool(3);}void ASkyCharacter::Tool5(){SetTool(4);}void ASkyCharacter::Tool6(){SetTool(5);}
void ASkyCharacter::Longer(){BoardLength=FMath::Min(600.f,BoardLength+10);}void ASkyCharacter::Shorter(){BoardLength=FMath::Max(30.f,BoardLength-10);}
void ASkyCharacter::Rotate(){PlacementYaw=FMath::Fmod(PlacementYaw+15,360.f);}
void ASkyCharacter::PitchPart(){PlacementPitch=FMath::Fmod(PlacementPitch+15.f,360.f);}
void ASkyCharacter::RollPart(){PlacementRoll=FMath::Fmod(PlacementRoll+15.f,360.f);}
void ASkyCharacter::Wider(){BoardWidth=FMath::Min(200.f,BoardWidth+2.f);}void ASkyCharacter::Narrower(){BoardWidth=FMath::Max(2.f,BoardWidth-2.f);}
void ASkyCharacter::Thicker(){BoardHeight=FMath::Min(100.f,BoardHeight+1.f);}void ASkyCharacter::Thinner(){BoardHeight=FMath::Max(1.f,BoardHeight-1.f);}
void ASkyCharacter::Primary(){if(MarketOpen){Buy();return;}ToolKick=1;ServerUse(static_cast<uint8>(Tool),static_cast<uint8>(BuildKind),FVector(BoardLength,BoardWidth,BoardHeight),FRotator(PlacementPitch,PlacementYaw,PlacementRoll));}
void ASkyCharacter::Secondary(){if(Tool==ESkyTool::Build) BuildKind=static_cast<ESkyBuildKind>((static_cast<int32>(BuildKind)+1)%3);else PreviousTool();}
void ASkyCharacter::ToggleMarket(){MarketOpen=!MarketOpen;}
void ASkyCharacter::Buy(){
    if(auto* W=ASkyWorld::Find(GetWorld())) if(!W->Offers.IsEmpty()) ServerTrade(true,W->Offers[MarketSelection%W->Offers.Num()].Id,0);
}
void ASkyCharacter::Sell(){
    // List five units of the most recently selected resource, purchased by the NPC only while it has a budget.
    const int32 Items[]={0,4,3,9,10,5};
    ServerTrade(false,0,Items[static_cast<int32>(Tool)]);
}
void ASkyCharacter::Save(){ServerSave();}
void ASkyCharacter::ServerUse_Implementation(uint8 T,uint8 Kind,FVector Size,FRotator Angles){
    const double Now=GetWorld()->GetTimeSeconds();
    if(Now-LastCommand<.22||T>5||Kind>2||Size.ContainsNaN()||Angles.ContainsNaN()||Health<=0)return;
    LastCommand=Now;
    FVector Start;FRotator View;GetActorEyesViewPoint(Start,View);
    Start=GetActorLocation()+FVector(0,0,64);
    FHitResult Hit;FCollisionQueryParams Params(SCENE_QUERY_STAT(SkyUse),false,this);
    if(GetWorld()->LineTraceSingleByChannel(Hit,Start,Start+View.Vector()*600,ECC_Visibility,Params))
        if(auto* W=ASkyWorld::Find(GetWorld()))W->Use(this,static_cast<ESkyTool>(T),Hit,static_cast<ESkyBuildKind>(Kind),FVector(FMath::Clamp(Size.X,30.0,600.0),FMath::Clamp(Size.Y,2.0,200.0),FMath::Clamp(Size.Z,1.0,100.0)),Angles.GetNormalized());
}
void ASkyCharacter::ServerTrade_Implementation(bool bBuy,int64 Offer,int32 Item){
    const double Now=GetWorld()->GetTimeSeconds();if(Now-LastCommand<.22)return;LastCommand=Now;
    if(auto* W=ASkyWorld::Find(GetWorld()))W->Trade(this,bBuy,Offer,Item);
}
void ASkyCharacter::ServerSave_Implementation(){
    // Only the listen-server host may trigger a global save. Dedicated server autosaves.
    if(IsLocallyControlled()) if(auto* W=ASkyWorld::Find(GetWorld()))W->SaveWorld();
}
void ASkyCharacter::ClientNotice_Implementation(const FString& Message){Notice=Message;}
int64 ASkyCharacter::Count(int32 Item)const{for(const auto& S:Inventory)if(S.Item==Item)return S.Quantity;return 0;}
float ASkyCharacter::TakeDamage(float Amount,const FDamageEvent&,AController*,AActor*){
    if(!HasAuthority()||!FMath::IsFinite(Amount)||Amount<=0)return 0;
    Health=FMath::Max(0.f,Health-Amount);
    if(Health<=0){SetActorLocation(FVector(-800,0,450));GetCharacterMovement()->StopMovementImmediately();Health=100;ClientNotice(TEXT("You were defeated. Respawned at the starter island."));}
    return Amount;
}
void ASkyCharacter::TouchBegin(ETouchIndex::Type F,FVector Pos){
    auto* PC=Cast<APlayerController>(Controller);if(!PC)return;
    const FVector2D P(Pos.X,Pos.Y);
    if(auto* H=Cast<ASkyHUD>(PC->GetHUD()))if(H->HandleTouch(P))return;
    int32 X,Y;PC->GetViewportSize(X,Y);
    if(P.X<X*.42f&&MoveTouch==INDEX_NONE){MoveTouch=(int32)F;TouchOrigin=P;}
    else if(LookTouch==INDEX_NONE){LookTouch=(int32)F;LastLook=P;}
}
void ASkyCharacter::TouchMoveEvent(ETouchIndex::Type F,FVector Pos){
    const FVector2D P(Pos.X,Pos.Y);
    if((int32)F==MoveTouch){const FVector2D D=(P-TouchOrigin)/90;TouchMove=FVector2D(FMath::Clamp(D.X,-1.0,1.0),FMath::Clamp(-D.Y,-1.0,1.0));}
    if((int32)F==LookTouch){FVector2D D=P-LastLook;Turn(D.X*.16f);Look(-D.Y*.16f);LastLook=P;}
}
void ASkyCharacter::TouchEnd(ETouchIndex::Type F,FVector){if((int32)F==MoveTouch){MoveTouch=INDEX_NONE;TouchMove=FVector2D::ZeroVector;}if((int32)F==LookTouch)LookTouch=INDEX_NONE;}
void ASkyCharacter::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& Out)const{
    Super::GetLifetimeReplicatedProps(Out);DOREPLIFETIME(ASkyCharacter,Account);DOREPLIFETIME(ASkyCharacter,Health);
    DOREPLIFETIME_CONDITION(ASkyCharacter,Coins,COND_OwnerOnly);DOREPLIFETIME_CONDITION(ASkyCharacter,Inventory,COND_OwnerOnly);
}
