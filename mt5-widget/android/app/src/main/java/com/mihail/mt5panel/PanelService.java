package com.mihail.mt5panel;

import android.app.*;
import android.content.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.provider.Settings;
import android.text.InputType;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;

public class PanelService extends Service {
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private SharedPreferences.OnSharedPreferenceChangeListener sizeListener;
    private WindowManager wm;private View current;private boolean expanded,busy,destroyed;
    private TextView status,details,account;private Spinner positions;private EditText tp,sl;private Button apply,refresh;
    private JSONArray rows=new JSONArray();private JSONObject selected;private Api api;private boolean needsRefresh=true;
    @Override public void onCreate(){
        super.onCreate();wm=(WindowManager)getSystemService(WINDOW_SERVICE);
        sizeListener=(prefs,key)->main.post(this::resizePanel);PanelSizePreferences.prefs(this).registerOnSharedPreferenceChangeListener(sizeListener);
        NotificationManager nm=getSystemService(NotificationManager.class);nm.createNotificationChannel(new NotificationChannel("panel","Боковая панель MT5",NotificationManager.IMPORTANCE_LOW));
        PendingIntent open=PendingIntent.getActivity(this,0,new Intent(this,MainActivity.class),PendingIntent.FLAG_IMMUTABLE);
        PendingIntent stop=PendingIntent.getService(this,1,new Intent(this,PanelService.class).setAction("STOP"),PendingIntent.FLAG_IMMUTABLE);
        startForeground(1,new Notification.Builder(this,"panel").setSmallIcon(android.R.drawable.ic_menu_manage).setContentTitle("MT5 • панель включена").setContentText("Ручка справа. Нажми, чтобы открыть настройки.").setContentIntent(open).setOngoing(true).addAction(new Notification.Action.Builder(null,"Остановить",stop).build()).build());
        try{api=new Api(this);}catch(Exception e){stopSelf();return;}
        if(!Settings.canDrawOverlays(this)){stopSelf();return;}show(false);
    }
    @Override public int onStartCommand(Intent i,int flags,int id){if(i!=null && "STOP".equals(i.getAction()))stopSelf();return START_NOT_STICKY;}
    @Override public IBinder onBind(Intent intent){return null;}
    private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
    private TextView text(String s,float size){TextView t=new TextView(this);t.setText(s);t.setTextSize(size);t.setTextColor(Color.WHITE);t.setPadding(dp(6),dp(4),dp(6),dp(4));return t;}
    private Button button(String s){Button b=new Button(this);b.setText(s);b.setFilterTouchesWhenObscured(true);return b;}
    private int[] panelDimensions(){
        android.util.DisplayMetrics dm=getResources().getDisplayMetrics();
        int width=dm.widthPixels,height=dm.heightPixels;
        if(Build.VERSION.SDK_INT>=30){
            WindowMetrics metrics=wm.getCurrentWindowMetrics();
            android.graphics.Insets insets=metrics.getWindowInsets().getInsetsIgnoringVisibility(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());
            width=metrics.getBounds().width()-insets.left-insets.right;
            height=metrics.getBounds().height()-insets.top-insets.bottom;
        }
        int usableWidth=Math.max(1,width-dp(16)),usableHeight=Math.max(1,height-dp(16));
        return new int[]{PanelSizeRules.dimension(usableWidth,dm.density,PanelSizePreferences.width(this),PanelSizeRules.MIN_WIDTH_PERCENT,PanelSizeRules.MAX_WIDTH_PERCENT,240),PanelSizeRules.dimension(usableHeight,dm.density,PanelSizePreferences.height(this),PanelSizeRules.MIN_HEIGHT_PERCENT,PanelSizeRules.MAX_HEIGHT_PERCENT,260)};
    }
    private void resizePanel(){
        if(destroyed||!expanded||current==null)return;
        int[] size=panelDimensions();
        WindowManager.LayoutParams p=(WindowManager.LayoutParams)current.getLayoutParams();
        p.width=size[0];p.height=size[1];
        try{wm.updateViewLayout(current,p);}catch(IllegalArgumentException ignored){}
    }
    @Override public void onConfigurationChanged(android.content.res.Configuration config){super.onConfigurationChanged(config);main.post(this::resizePanel);}
    private void show(boolean open){
        if(destroyed)return;
        if(current!=null){wm.removeView(current);current=null;}
        expanded=open;
        WindowManager.LayoutParams p=new WindowManager.LayoutParams(open?panelDimensions()[0]:dp(26),open?panelDimensions()[1]:dp(100),WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,open?WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL:WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,PixelFormat.TRANSLUCENT);
        p.gravity=Gravity.RIGHT|Gravity.CENTER_VERTICAL;p.softInputMode=WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE;
        LinearLayout box=new LinearLayout(this);box.setOrientation(LinearLayout.VERTICAL);box.setPadding(dp(open?8:0),dp(4),dp(open?8:0),dp(4));GradientDrawable bg=new GradientDrawable();bg.setColor(Color.rgb(20,26,35));bg.setCornerRadius(dp(18));bg.setStroke(dp(1),Color.rgb(32,201,153));box.setBackground(bg);
        TextView header=text(open?"MT5 Панель       → свернуть":"‹",open?19:26);header.setGravity(Gravity.CENTER);box.addView(header);header.setOnClickListener(v->show(!expanded));
        header.setOnTouchListener(new View.OnTouchListener(){float x;public boolean onTouch(View v,android.view.MotionEvent e){if(e.getAction()==MotionEvent.ACTION_DOWN){x=e.getRawX();return true;}if(e.getAction()==MotionEvent.ACTION_UP){float dx=e.getRawX()-x;if(Math.abs(dx)<dp(10))v.performClick();else if((!expanded && dx< -dp(20))||(expanded && dx>dp(20)))show(!expanded);return true;}return true;}});
        if(open){
            account=text("Счёт: загрузка…",13);box.addView(account);
            positions=new Spinner(this);box.addView(positions);details=text("Выбери позицию",13);box.addView(details);
            tp=new EditText(this);tp.setSingleLine();tp.setHint("TP: расстояние от входа");tp.setTextColor(Color.WHITE);tp.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_FLAG_DECIMAL);tp.setFilterTouchesWhenObscured(true);box.addView(tp);
            sl=new EditText(this);sl.setSingleLine();sl.setHint("SL: расстояние от входа");sl.setTextColor(Color.WHITE);sl.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_FLAG_DECIMAL);sl.setFilterTouchesWhenObscured(true);box.addView(sl);
            box.addView(text("Пустое поле = оставить как есть.\n0.25 означает изменение цены на 0.25.",12));
            LinearLayout buttons=new LinearLayout(this);refresh=button("Обновить");apply=button("Применить");buttons.addView(refresh,new LinearLayout.LayoutParams(0,-2,1));buttons.addView(apply,new LinearLayout.LayoutParams(0,-2,1));box.addView(buttons);
            status=text("",13);box.addView(status);refresh.setOnClickListener(v->load());apply.setOnClickListener(v->submit());
            positions.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener(){public void onNothingSelected(AdapterView<?> p){selected=null;}public void onItemSelected(AdapterView<?> p,View v,int pos,long id){selected=rows.optJSONObject(pos);tp.setText("");sl.setText("");renderPosition();}});
            box.removeView(header);ScrollView scroll=new ScrollView(this);scroll.setFillViewport(false);scroll.addView(box);LinearLayout frame=new LinearLayout(this);frame.setOrientation(LinearLayout.VERTICAL);frame.setBackground(bg);box.setBackground(null);frame.addView(header);frame.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));current=frame;try{wm.addView(current,p);}catch(Exception e){stopSelf();return;}load();
        } else {current=box;try{wm.addView(current,p);}catch(Exception e){stopSelf();}}
    }
    private void renderPosition(){if(selected==null){details.setText("Открытых позиций нет");return;}details.setText(selected.optString("symbol")+" • "+selected.optString("side")+" • "+selected.optString("volume")+"\nТикет: "+selected.optString("ticket")+"\nВход: "+selected.optString("price_open")+"\nTP: "+selected.optString("tp")+"   SL: "+selected.optString("sl"));}
    private void enabled(){if(!expanded)return;refresh.setEnabled(!busy);apply.setEnabled(!busy&&!needsRefresh&&selected!=null);positions.setEnabled(!busy);tp.setEnabled(!busy);sl.setEnabled(!busy);}
    private void load(){
        if(busy){if(expanded){status.setText("Запрос ещё выполняется. Не отправляй повторно.");enabled();}return;}
        busy=true;needsRefresh=true;enabled();status.setText("Загрузка позиций…");
        worker.execute(()->{try{JSONObject health=api.request("/health",null);JSONObject result=api.request("/api/positions",null);main.post(()->{busy=false;if(destroyed||!expanded)return;rows=result.optJSONArray("positions");if(rows==null)rows=new JSONArray();ArrayList<String> labels=new ArrayList<>();for(int i=0;i<rows.length();i++){JSONObject r=rows.optJSONObject(i);labels.add(r.optString("symbol")+" "+r.optString("side")+" #"+r.optString("ticket"));}positions.setAdapter(new ArrayAdapter<String>(this,android.R.layout.simple_spinner_dropdown_item,labels));selected=rows.optJSONObject(0);tp.setText("");sl.setText("");JSONObject a=result.optJSONObject("account");String login=a!=null?a.optString("login"):result.optString("account","не указан");String server=a!=null?a.optString("server"):result.optString("server");account.setText("Счёт: "+login+" • "+server+"\nРежим: "+("live".equals(health.optString("mode"))?"РЕАЛЬНЫЕ ИЗМЕНЕНИЯ":"только чтение / dry_run"));needsRefresh=false;renderPosition();status.setText(rows.length()==0?"Открытых позиций нет":"Позиции обновлены. Выбери нужный тикет.");enabled();});}catch(Exception e){main.post(()->{busy=false;if(!destroyed&&expanded){needsRefresh=true;status.setText("Не удалось загрузить позиции. "+safeError(e));enabled();}});}});
    }
    private static String safeError(Exception e){if(e instanceof javax.net.ssl.SSLException)return "Ошибка сертификата HTTPS. Проверку безопасности не отключаем.";if(e instanceof java.net.SocketTimeoutException)return "Время ожидания истекло.";if(e instanceof java.io.IOException)return "Проверь соединение с VPS.";return e.getMessage()==null?"Неизвестная ошибка":e.getMessage();}
    private Double distance(EditText field){String s=field.getText().toString().trim().replace(',','.');if(s.isEmpty())return null;double d=Double.parseDouble(s);if(!Double.isFinite(d)||d<=0)throw new IllegalArgumentException();return d;}
    private void submit(){
        if(busy||needsRefresh||selected==null)return;
        try{
            Double td=distance(tp),sd=distance(sl);if(td==null&&sd==null){status.setText("Укажи хотя бы одно расстояние");return;}
            JSONObject chosen=new JSONObject(selected.toString());
            JSONObject body=new JSONObject().put("request_id",UUID.randomUUID().toString()).put("expected_entry",chosen.getDouble("price_open")).put("expected_symbol",chosen.getString("symbol")).put("expected_side",chosen.getString("side")).put("expected_volume",chosen.getDouble("volume")).put("expected_identifier",chosen.getLong("identifier"));
            if(td!=null)body.put("tp_distance",td);if(sd!=null)body.put("sl_distance",sd);
            busy=true;needsRefresh=true;enabled();status.setText("Отправлено в MT5. Ждём проверку…");
            worker.execute(()->{try{JSONObject result=api.request("/api/positions/"+chosen.getLong("ticket")+"/protection",body);main.post(()->{busy=false;if(destroyed||!expanded)return;String state=result.optString("status");if("verified".equals(state)){status.setText("Уровни подтверждены MT5 для #"+chosen.optString("ticket")+". Нажми «Обновить» перед следующим изменением.");JSONObject pos=result.optJSONObject("position");if(pos!=null){selected=pos;renderPosition();}tp.setText("");sl.setText("");}else if("rejected".equals(state)){status.setText("Изменение отклонено: "+result.optString("message")+". Обнови позиции.");}else{status.setText("Результат не подтверждён. Не повторяй команду вслепую. Обнови позиции и проверь TP/SL в MT5.");}enabled();});}catch(Exception e){main.post(()->{busy=false;if(!destroyed&&expanded){status.setText("Результат неизвестен: "+safeError(e)+" Обнови позиции и проверь TP/SL в MT5 перед повторной попыткой.");enabled();}});}});
        }catch(Exception e){status.setText("Введи положительное расстояние, например 0.25. Ноль не удаляет защиту.");}
    }
    @Override public void onDestroy(){destroyed=true;if(sizeListener!=null)PanelSizePreferences.prefs(this).unregisterOnSharedPreferenceChangeListener(sizeListener);worker.shutdown();main.removeCallbacksAndMessages(null);if(current!=null){try{wm.removeView(current);}catch(Exception ignored){}current=null;}stopForeground(STOP_FOREGROUND_REMOVE);super.onDestroy();}
}
