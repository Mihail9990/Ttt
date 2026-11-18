package com.mihail.mt5panel;

/** Android-independent geometry and gesture policy. */
final class PanelDockRules {
    static final int LEFT=0, RIGHT=1, BOTTOM=2;
    static int edge(int value){return value>=LEFT&&value<=BOTTOM?value:RIGHT;}
    static int scale(int value){return Math.max(75,Math.min(150,value));}
    static float fraction(float value){return Float.isFinite(value)?Math.max(0,Math.min(1,value)):0.5f;}
    static int nearest(float x,float y,int width,int height){
        float left=Math.abs(x),right=Math.abs(width-x),bottom=Math.abs(height-y);
        return bottom<=Math.min(left,right)?BOTTOM:(left<right?LEFT:RIGHT);
    }
    static boolean swipe(int edge,boolean open,float dx,float dy,float threshold){
        float inward=edge==LEFT?dx:edge==RIGHT?-dx:-dy;
        float across=edge==BOTTOM?Math.abs(dx):Math.abs(dy);
        return (open?-inward:inward)>threshold && Math.abs(inward)>across;
    }
    static int[] position(int edge,float fraction,int screenWidth,int screenHeight,int width,int height){
        int maxX=Math.max(0,screenWidth-width),maxY=Math.max(0,screenHeight-height);
        if(edge==BOTTOM)return new int[]{Math.round(maxX*fraction(fraction)),maxY};
        return new int[]{edge==LEFT?0:maxX,Math.round(maxY*fraction(fraction))};
    }
}
