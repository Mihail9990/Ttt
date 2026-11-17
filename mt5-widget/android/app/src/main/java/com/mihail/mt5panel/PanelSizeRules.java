package com.mihail.mt5panel;

/** Pure sizing rules. Dimensions are clamped even if stored preferences are corrupt. */
final class PanelSizeRules {
    static final int MIN_WIDTH_PERCENT=35, MAX_WIDTH_PERCENT=95, DEFAULT_WIDTH_PERCENT=85;
    static final int MIN_HEIGHT_PERCENT=25, MAX_HEIGHT_PERCENT=90, DEFAULT_HEIGHT_PERCENT=75;
    static int clamp(int value,int min,int max){return Math.max(min,Math.min(max,value));}
    static int widthPercent(int value){return clamp(value,MIN_WIDTH_PERCENT,MAX_WIDTH_PERCENT);}
    static int heightPercent(int value){return clamp(value,MIN_HEIGHT_PERCENT,MAX_HEIGHT_PERCENT);}
    static int dimension(int availablePx,float density,int requestedPercent,int minPercent,int maxPercent,int minDp){
        int available=Math.max(1,availablePx);
        float safeDensity=Float.isFinite(density)&&density>0?density:1;
        int minimum=Math.min(available,Math.max(1,Math.round(minDp*safeDensity)));
        int requested=(int)Math.round(available*(clamp(requestedPercent,minPercent,maxPercent)/100.0));
        return Math.min(available,Math.max(minimum,requested));
    }
}
