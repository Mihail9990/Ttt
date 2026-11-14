#include "SkyGameMode.h"
#include "Engine/World.h"
#include "Engine/StaticMesh.h"
#include "Engine/DamageEvents.h"
#include "SkyCharacter.h"
#include "SkyHUD.h"
#include "SkyWorld.h"
ASkyGameMode::ASkyGameMode(){DefaultPawnClass=ASkyCharacter::StaticClass();HUDClass=ASkyHUD::StaticClass();}
void ASkyGameMode::InitGame(const FString& Map,const FString& Options,FString& Error){
    Super::InitGame(Map,Options,Error);
    if(!ASkyWorld::Find(GetWorld()))GetWorld()->SpawnActor<ASkyWorld>();
}
