package com.mihail.mt5panel;

import android.app.*;
import android.content.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.drawable.GradientDrawable;
import android.provider.Settings;

/** Overlay shell only. No trading commands are issued by gestures or sizing. */
public class PanelService extends Service {
    private final Handler main=new Handler(Looper.getMainLooper());
    private WindowManager wm;
    private View current;
    private RecoveryPanelView recovery;
    private boolean expanded,destroyed;
    private int edge=PanelDockRules.RIGHT;
    private float anchor=0.5f;
    private SharedPreferences prefs;
    private SharedPreferences.OnSharedPreferenceChangeListener listener;
    private Runnable pendingHold;
    @Override public void onCreate(){
        super.onCreate();wm=(WindowManager)getSystemService(WINDOW_SERVICE);
        prefs=PanelSizePreferences.prefs(this);
        edge=PanelDockRules.edge(prefs.getInt("dock_edge",PanelDockRules.RIGHT));
        anchor=PanelDockRules.fraction(prefs.getFloat("dock_anchor",0.5f));
        listener=(p,k)->{if(!"dock_edge".equals(k)&&!"dock_anchor".equals(k))main.post(()->{if(!destroyed)show(expanded);});};
        prefs.registerOnSharedPreferenceChangeListener(listener);
        NotificationManager nm=getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel("panel","Панель MT5",NotificationManager.IMPORTANCE_LOW));
        PendingIntent open=PendingIntent.getActivity(this,0,new Intent(this,MainActivity.class),PendingIntent.FLAG_IMMUTABLE);
        PendingIntent stop=PendingIntent.getService(this,1,new Intent(this,PanelService.class).setAction("STOP"),PendingIntent.FLAG_IMMUTABLE);
        startForeground(1,new Notification.Builder(this,"panel").setSmallIcon(android.R.drawable.ic_menu_manage)
            .setContentTitle("MT5 • панель включена").setContentText("Удерживай значок, чтобы переместить. Нажми для настроек.")
            .setContentIntent(open).setOngoing(true).addAction(new Notification.Action.Builder(null,"Остановить",stop).build()).build());
        if(!Settings.canDrawOverlays(this)){stopSelf();return;}show(false);
    }
    @Override public int onStartCommand(Intent i,int flags,int id){if(i!=null&&"STOP".equals(i.getAction()))stopSelf();return START_NOT_STICKY;}
    @Override public IBinder onBind(Intent i){return null;}
    private int dp(float n){return Math.round(n*getResources().getDisplayMetrics().density);}
    private float scale(){return PanelDockRules.scale(prefs.getInt("ui_scale",100))/100f;}
    private TextView text(String value,float size){TextView t=new TextView(this);t.setText(value);t.setTextSize(size*scale());t.setTextColor(Color.WHITE);t.setPadding(dp(8),dp(6),dp(8),dp(6));return t;}
    private Rect safeBounds(){
        if(Build.VERSION.SDK_INT>=30){WindowMetrics m=wm.getCurrentWindowMetrics();android.graphics.Insets i=m.getWindowInsets().getInsetsIgnoringVisibility(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());Rect b=m.getBounds();return new Rect(i.left,i.top,b.width()-i.right,b.height()-i.bottom);}
        android.util.DisplayMetrics m=new android.util.DisplayMetrics();wm.getDefaultDisplay().getRealMetrics(m);
        int statusId=getResources().getIdentifier("status_bar_height","dimen","android"),navId=getResources().getIdentifier("navigation_bar_height","dimen","android");
        int top=statusId>0?getResources().getDimensionPixelSize(statusId):dp(24),bottom=navId>0?getResources().getDimensionPixelSize(navId):dp(48);
        return new Rect(0,top,m.widthPixels,Math.max(top+1,m.heightPixels-bottom));
    }
    private int[] dimensions(boolean open){
        Rect b=safeBounds();float density=getResources().getDisplayMetrics().density;
        if(!open){int shortSide=dp(48*scale()),longSide=dp(68*scale());return new int[]{Math.min(b.width(),edge==PanelDockRules.BOTTOM?longSide:shortSide),Math.min(b.height(),edge==PanelDockRules.BOTTOM?shortSide:longSide)};}
        return new int[]{PanelSizeRules.dimension(b.width(),density,PanelSizePreferences.width(this),35,95,240),PanelSizeRules.dimension(b.height(),density,PanelSizePreferences.height(this),25,90,260)};
    }
    private void place(WindowManager.LayoutParams p){Rect b=safeBounds();int[] xy=PanelDockRules.position(edge,anchor,b.width(),b.height(),p.width,p.height);p.x=b.left+xy[0];p.y=b.top+xy[1];}
    private void cancelHold(){if(pendingHold!=null){main.removeCallbacks(pendingHold);pendingHold=null;}}
    private void show(boolean open){
        if(destroyed)return;cancelHold();
        if(current!=null){current.animate().cancel();wm.removeView(current);current=null;}
        expanded=open;if(recovery!=null)recovery.setActive(open);int[] size=dimensions(open);
        WindowManager.LayoutParams p=new WindowManager.LayoutParams(size[0],size[1],WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN|(open?WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL:WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE),PixelFormat.TRANSLUCENT);
        p.gravity=Gravity.TOP|Gravity.LEFT;place(p);
        GradientDrawable bg=new GradientDrawable();bg.setColor(Color.rgb(20,26,35));bg.setCornerRadius(dp(16));bg.setStroke(dp(1),Color.rgb(32,201,153));
        LinearLayout frame=new LinearLayout(this);frame.setOrientation(LinearLayout.VERTICAL);frame.setBackground(bg);
        String arrow=edge==PanelDockRules.LEFT?">":edge==PanelDockRules.RIGHT?"<":"⌃";
        TextView header=text(open?"MT5  •  свернуть":arrow,open?18:28);header.setGravity(Gravity.CENTER);header.setMinHeight(dp(48));
        header.setContentDescription(open?"Свернуть панель":"Открыть панель. Удерживайте для перемещения");
        frame.addView(header,new LinearLayout.LayoutParams(-1,open?-2:-1));header.setOnClickListener(v->show(!expanded));
        header.setOnTouchListener(new View.OnTouchListener(){
            float x,y;int startX,startY;boolean dragging,moved;
            public boolean onTouch(View v,MotionEvent e){
                float dx=e.getRawX()-x,dy=e.getRawY()-y;
                switch(e.getActionMasked()){
                    case MotionEvent.ACTION_DOWN:
                        x=e.getRawX();y=e.getRawY();startX=p.x;startY=p.y;dragging=false;moved=false;
                        if(!expanded){pendingHold=()->{dragging=true;v.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);};main.postDelayed(pendingHold,ViewConfiguration.getLongPressTimeout());}return true;
                    case MotionEvent.ACTION_MOVE:
                        if(!dragging && Math.hypot(dx,dy)>ViewConfiguration.get(PanelService.this).getScaledTouchSlop()){moved=true;cancelHold();}
                        if(dragging){Rect b=safeBounds();p.x=Math.max(b.left,Math.min(b.right-p.width,startX+Math.round(dx)));p.y=Math.max(b.top,Math.min(b.bottom-p.height,startY+Math.round(dy)));wm.updateViewLayout(current,p);}return true;
                    case MotionEvent.ACTION_UP:
                        cancelHold();
                        if(dragging){Rect b=safeBounds();float cx=p.x-b.left+p.width/2f,cy=p.y-b.top+p.height/2f;edge=PanelDockRules.nearest(cx,cy,b.width(),b.height());anchor=PanelDockRules.fraction(edge==PanelDockRules.BOTTOM?(p.x-b.left)/(float)Math.max(1,b.width()-p.width):(p.y-b.top)/(float)Math.max(1,b.height()-p.height));prefs.edit().putInt("dock_edge",edge).putFloat("dock_anchor",anchor).apply();show(false);}
                        else if(PanelDockRules.swipe(edge,expanded,dx,dy,dp(24)))show(!expanded);
                        else if(!moved && Math.hypot(dx,dy)<dp(10))v.performClick();return true;
                    case MotionEvent.ACTION_CANCEL:cancelHold();if(dragging)show(false);return true;
                    default:return true;
                }
            }
        });
        if(open){
            LinearLayout content=new LinearLayout(this);content.setOrientation(LinearLayout.VERTICAL);content.setPadding(dp(8),0,dp(8),dp(12));
            if(recovery==null)recovery=new RecoveryPanelView(this);
            if(recovery.getParent()!=null)((ViewGroup)recovery.getParent()).removeView(recovery);
            recovery.setScale(scale());content.addView(recovery);recovery.setActive(true);
            content.addView(text("Масштаб: "+Math.round(scale()*100)+" %",15));
            LinearLayout buttons=new LinearLayout(this);
            addButton(buttons,"−",()->setScale(Math.round(scale()*100)-10));addButton(buttons,"+",()->setScale(Math.round(scale()*100)+10));content.addView(buttons);
            addButton(content,"Размер и настройки",()->startActivity(new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)));
            ScrollView scroll=new ScrollView(this);scroll.addView(content);frame.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        }
        current=frame;try{wm.addView(current,p);}catch(Exception ex){stopSelf();return;}
        if(open){if(edge==PanelDockRules.BOTTOM)frame.setTranslationY(p.height);else frame.setTranslationX(edge==PanelDockRules.LEFT?-p.width:p.width);frame.animate().translationX(0).translationY(0).setDuration(180).start();}
    }
    private void setScale(int value){prefs.edit().putInt("ui_scale",PanelDockRules.scale(value)).apply();}
    private void addButton(LinearLayout box,String label,Runnable click){Button b=new Button(this);b.setText(label);b.setTextSize(14*scale());b.setFilterTouchesWhenObscured(true);b.setOnClickListener(v->click.run());box.addView(b);}
    @Override public void onConfigurationChanged(android.content.res.Configuration c){super.onConfigurationChanged(c);main.post(()->show(expanded));}
    @Override public void onDestroy(){destroyed=true;if(recovery!=null)recovery.dispose();cancelHold();main.removeCallbacksAndMessages(null);if(listener!=null)prefs.unregisterOnSharedPreferenceChangeListener(listener);if(current!=null){current.animate().cancel();try{wm.removeView(current);}catch(Exception ignored){}current=null;}stopForeground(STOP_FOREGROUND_REMOVE);super.onDestroy();}
}
