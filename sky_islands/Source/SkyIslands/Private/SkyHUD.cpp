#include "SkyHUD.h"
#include "SkyCharacter.h"
#include "SkyWorld.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "GameFramework/PlayerController.h"
namespace {
const TCHAR* Tools[]={TEXT("Лопата"),TEXT("Топор"),TEXT("Кирка"),TEXT("Молоток"),TEXT("Шуруповёрт"),TEXT("Строительство")};
const TCHAR* Items[]={TEXT("Земля"),TEXT("Глина"),TEXT("Песок"),TEXT("Камень"),TEXT("Древесина"),TEXT("Доски"),TEXT("Кирпич"),TEXT("Руда"),TEXT("Металл"),TEXT("Гвозди"),TEXT("Саморезы"),TEXT("Топливо")};
}
void ASkyHUD::DrawHUD(){
    Super::DrawHUD();auto* P=Cast<ASkyCharacter>(GetOwningPawn());if(!P||!Canvas)return;
    const float W=Canvas->SizeX,H=Canvas->SizeY,Scale=FMath::Clamp(W/1500.f,.65f,1.4f);
    auto Text=[&](const FString& S,float X,float Y,FLinearColor Color=FLinearColor::White){DrawText(S,Color,X,Y,GEngine->GetSmallFont(),Scale);};
    DrawRect(FLinearColor(.025,.04,.055,.8),16,16,W*.5f,90);
    Text(TEXT("НЕБЕСНЫЕ ОСТРОВА · UE5 / ранняя версия"),30,26);
    Text(FString::Printf(TEXT("Здоровье %.0f    Монеты %lld"),P->Health,(long long)P->Coins),30,50);
    Text(FString::Printf(TEXT("%s    Доски %lld    Гвозди %lld    Саморезы %lld"),Tools[(int32)P->Tool],(long long)P->Count(5),(long long)P->Count(9),(long long)P->Count(10)),30,74);
    DrawLine(W/2-7,H/2,W/2+7,H/2,FLinearColor::White,1);DrawLine(W/2,H/2-7,W/2,H/2+7,FLinearColor::White,1);
    Text(P->Notice,30,H-170);
    if(P->Tool==ESkyTool::Build)Text(FString::Printf(TEXT("Размер %.0f × %.0f × %.0f см    Углы %.0f / %.0f / %.0f"),P->BoardLength,P->BoardWidth,P->BoardHeight,P->PlacementPitch,P->PlacementYaw,P->PlacementRoll),30,H-145);
    Text(TEXT("WASD: ходьба · 1–6: инструмент · ЛКМ: действие · ПКМ: вид детали · R/Q/C: поворот · +/- [ ] ; ': размеры · M: рынок · F5: сохранить"),30,H-115,FLinearColor(.8,.85,.9));
    const TCHAR* Buttons[]={TEXT("ИНСТР."),TEXT("ДЕТАЛЬ"),TEXT("ПОВОРОТ"),TEXT("ПРЫЖОК"),TEXT("РЫНОК"),TEXT("ДЕЙСТВИЕ")};
    for(int I=0;I<6;++I){float X=W*(.015f+I*.164f);DrawRect(FLinearColor(.06,.14,.19,.85),X,H-72,W*.151f,55);Text(Buttons[I],X+8,H-55);}
    if(P->MarketOpen){
        DrawRect(FLinearColor(.025,.035,.05,.97),W*.15f,H*.15f,W*.7f,H*.64f);
        Text(TEXT("МАРКЕТПЛЕЙС · NPC И ИГРОКИ"),W*.18f,H*.18f);
        auto* World=ASkyWorld::Find(GetWorld());
        if(World){const int Count=World->Offers.Num();P->MarketSelection=Count?P->MarketSelection%Count:0;
            const int Start=P->MarketSelection/6*6;
            for(int I=Start;I<FMath::Min(Start+6,Count);++I){const auto& O=World->Offers[I];float Y=H*.26f+(I-Start)*H*.06f;
                if(I==P->MarketSelection)DrawRect(FLinearColor(.08,.29,.34,.9),W*.17f,Y-4,W*.64f,H*.055f);
                Text(FString::Printf(TEXT("%s × %lld    %lld монет    %s"),Items[FMath::Clamp(O.Item,0,11)],(long long)O.Quantity,(long long)O.Price,O.Seller==900000?TEXT("Торговец NPC"):TEXT("Игрок")),W*.19f,Y);
            }}
        DrawRect(FLinearColor(.1,.3,.32,1),W*.18f,H*.63f,W*.28f,H*.05f);Text(TEXT("КУПИТЬ"),W*.2f,H*.64f);
        DrawRect(FLinearColor(.24,.18,.12,1),W*.49f,H*.63f,W*.28f,H*.05f);Text(TEXT("ПРОДАТЬ РЕСУРС"),W*.51f,H*.64f);
        Text(TEXT("Колесо: выбрать · B / ДЕЙСТВИЕ: купить · Z: продать до 5 ед. выбранного ресурса · M: закрыть"),W*.18f,H*.69f);
        Text(TEXT("Добытые ресурсы: лопата — земля, топор — древесина, кирка — камень."),W*.18f,H*.73f);
    }
}
bool ASkyHUD::HandleTouch(FVector2D P){
    auto* C=Cast<ASkyCharacter>(GetOwningPawn());if(!Canvas||!C)return false;
    const float W=Canvas->SizeX,H=Canvas->SizeY;
    if(P.Y>=H-82){const int I=FMath::Clamp((int)(P.X/W*6),0,5);switch(I){case 0:C->NextTool();break;case 1:C->Secondary();break;case 2:C->Rotate();break;case 3:C->Jump();break;case 4:C->ToggleMarket();break;case 5:C->Primary();break;}return true;}
    if(C->MarketOpen){
        if(P.Y>H*.63&&P.Y<H*.68){if(P.X>W*.18&&P.X<W*.46)C->Buy();else if(P.X>W*.49&&P.X<W*.77)C->Sell();return true;}
        if(P.X>W*.17&&P.X<W*.82&&P.Y>H*.25&&P.Y<H*.63){C->MarketSelection=C->MarketSelection/6*6+FMath::Clamp((int)((P.Y-H*.26)/(H*.06)),0,5);}return true;}
    return false;
}
