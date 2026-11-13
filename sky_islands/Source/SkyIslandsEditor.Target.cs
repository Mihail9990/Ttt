using UnrealBuildTool;
using System.Collections.Generic;

public class SkyIslandsEditorTarget : TargetRules
{
    public SkyIslandsEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V5;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_6;
        ExtraModuleNames.Add("SkyIslands");
    }
}
