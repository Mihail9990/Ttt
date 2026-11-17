package com.mihail.mt5panel;
public class PanelSizeTest {
    static int checks;
    static void eq(int a,int b){checks++;if(a!=b)throw new AssertionError(a+" != "+b);}
    static void within(int result,int available){checks++;if(result<1||result>Math.max(1,available))throw new AssertionError("outside screen: "+result+"/"+available);}
    public static void main(String[] args){
        eq(PanelSizeRules.widthPercent(-999),35);eq(PanelSizeRules.widthPercent(999),95);
        eq(PanelSizeRules.heightPercent(-1),25);eq(PanelSizeRules.heightPercent(100),90);
        eq(PanelSizeRules.dimension(1000,1,85,35,95,240),850);
        eq(PanelSizeRules.dimension(1000,1,75,25,90,260),750);
        eq(PanelSizeRules.dimension(340,1,35,35,95,240),240);
        eq(PanelSizeRules.dimension(200,1,95,35,95,240),200);
        eq(PanelSizeRules.dimension(0,1,85,35,95,240),1);
        for(int screen:new int[]{1,200,320,480,720,1080,1920})
            for(float density:new float[]{1,1.5f,2,3,Float.NaN})
                for(int percent:new int[]{Integer.MIN_VALUE,0,25,35,75,85,95,100,Integer.MAX_VALUE}){
                    within(PanelSizeRules.dimension(screen,density,percent,35,95,240),screen);
                    within(PanelSizeRules.dimension(screen,density,percent,25,90,260),screen);
                }
        System.out.println(checks+" panel sizing checks passed");
    }
}
