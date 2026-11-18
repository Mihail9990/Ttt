package com.mihail.mt5panel;
public class PanelDockTest {
    static int count;
    static void check(boolean ok){count++;if(!ok)throw new AssertionError("check "+count);}
    public static void main(String[] args){
        check(PanelDockRules.nearest(5,300,400,800)==PanelDockRules.LEFT);
        check(PanelDockRules.nearest(395,300,400,800)==PanelDockRules.RIGHT);
        check(PanelDockRules.nearest(200,795,400,800)==PanelDockRules.BOTTOM);
        for(int e=0;e<3;e++){
            float dx=e==0?50:e==1?-50:0,dy=e==2?-50:0;
            check(PanelDockRules.swipe(e,false,dx,dy,24));check(!PanelDockRules.swipe(e,true,dx,dy,24));
            check(PanelDockRules.swipe(e,true,-dx,-dy,24));check(!PanelDockRules.swipe(e,false,-dx,-dy,24));
            check(!PanelDockRules.swipe(e,false,dx/10,dy/10,24));check(!PanelDockRules.swipe(e,false,50,50,24));
            for(int w:new int[]{100,360,800})for(int h:new int[]{100,640,1000})for(float f:new float[]{-1,0,.25f,.5f,1,2,Float.NaN}){
                int[] xy=PanelDockRules.position(e,f,w,h,80,90);check(xy[0]>=0&&xy[0]+80<=w);check(xy[1]>=0&&xy[1]+90<=h);
                if(e==0)check(xy[0]==0);if(e==1)check(xy[0]==w-80);if(e==2)check(xy[1]==h-90);
            }
        }
        check(PanelDockRules.scale(1)==75);check(PanelDockRules.scale(200)==150);check(PanelDockRules.scale(100)==100);
        check(PanelDockRules.edge(-1)==PanelDockRules.RIGHT);check(PanelDockRules.fraction(Float.NaN)==.5f);
        System.out.println("PanelDockTest passed: "+count);
    }
}
