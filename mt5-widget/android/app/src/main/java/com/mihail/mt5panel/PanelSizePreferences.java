package com.mihail.mt5panel;

import android.content.Context;
import android.content.SharedPreferences;

final class PanelSizePreferences {
    static final String WIDTH="width_percent", HEIGHT="height_percent";
    static SharedPreferences prefs(Context c){return c.getSharedPreferences("panel_size",Context.MODE_PRIVATE);}
    static int width(Context c){try{return PanelSizeRules.widthPercent(prefs(c).getInt(WIDTH,PanelSizeRules.DEFAULT_WIDTH_PERCENT));}catch(ClassCastException e){return PanelSizeRules.DEFAULT_WIDTH_PERCENT;}}
    static int height(Context c){try{return PanelSizeRules.heightPercent(prefs(c).getInt(HEIGHT,PanelSizeRules.DEFAULT_HEIGHT_PERCENT));}catch(ClassCastException e){return PanelSizeRules.DEFAULT_HEIGHT_PERCENT;}}
    static void save(Context c,int width,int height){prefs(c).edit().putInt(WIDTH,PanelSizeRules.widthPercent(width)).putInt(HEIGHT,PanelSizeRules.heightPercent(height)).apply();}
}
