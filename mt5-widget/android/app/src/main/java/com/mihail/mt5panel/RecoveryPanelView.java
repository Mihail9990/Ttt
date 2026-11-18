package com.mihail.mt5panel;

import android.content.Context;
import android.graphics.Color;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.View;
import android.view.ViewGroup;
import android.widget.*;
import org.json.*;
import java.util.UUID;
import java.util.concurrent.*;

/** RECOVERY controls: versioned native state or explicitly labelled simulation. */
final class RecoveryPanelView extends LinearLayout {
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final TextView status,summary;
    private final EditText[] price=new EditText[2],volume=new EditText[2];
    private final Spinner[] side=new Spinner[2];
    private final EditText initialSl,reentry;
    private boolean distancesEdited,distancesLoaded;
    private final LinearLayout second;
    private final Button place,cancel,close1,close2,refresh;
    private boolean two,busy,valid,active;
    private volatile boolean disposed;
    private static final Object DISPATCH_LOCK=new Object();
    private JSONObject state;
    private NativeWidgetState nativeState;
    private final android.content.SharedPreferences pending,attempted;
    private final Runnable poll=()->{if(active&&!disposed)fetch(null,null);};
    RecoveryPanelView(Context c){
        super(c);setOrientation(VERTICAL);
        pending=c.getSharedPreferences("recovery-pending-command",0);
        attempted=c.getSharedPreferences("recovery-attempted-ids",0);
        addView(label("RECOVERY • КОНТРОЛЬ VPS",19));
        addView(label("Режим счёта и доступные действия подтверждаются VPS. В native-режиме кнопки могут отправлять реальные торговые команды.",14));
        addView(label("Настройки расстояний (единицы цены)",17));
        addView(label("Исходный SL от цены входа (минимум 0,60)",14));
        initialSl=field("Например 0.70",RecoveryDistances.DEFAULT);addView(initialSl);
        addView(label("Повторный триггер от SL поддержки",14));
        reentry=field("Например 0.70",RecoveryDistances.DEFAULT);addView(reentry);
        TextWatcher edited=new TextWatcher(){public void beforeTextChanged(CharSequence s,int start,int count,int after){} public void onTextChanged(CharSequence s,int start,int before,int count){distancesEdited=true;} public void afterTextChanged(Editable e){}};
        initialSl.addTextChangedListener(edited);reentry.addTextChangedListener(edited);
        addView(label("Это независимые настройки. Применяются вместе с подтверждением новых диапазонов; отдельное изменение действующих SL не выполняется.",13));
        LinearLayout choices=new LinearLayout(c);
        button(choices,"1 диапазон",()->{two=false;secondVisibility();});
        button(choices,"2 диапазона",()->{two=true;secondVisibility();});addView(choices);
        addView(range(0));second=range(1);addView(second);second.setVisibility(GONE);
        place=button(this,"Подтвердить диапазоны",this::placeRanges);
        refresh=button(this,"Обновить состояние",()->fetch(null,null));
        cancel=button(this,"Отменить диапазоны и ждать",()->command("/api/recovery/cancel",new JSONObject()));
        close1=button(this,"Закрыть позицию и отменить №1",()->command("/api/recovery/ranges/1/close-cancel",new JSONObject()));
        close2=button(this,"Закрыть позицию и отменить №2",()->command("/api/recovery/ranges/2/close-cancel",new JSONObject()));
        addView(label("Закрыть и отменить: закрывает позицию выбранного диапазона и отменяет его триггеры. Обычное ручное закрытие выполняй в Bybit.",13));
        status=label("Нет подтверждённого соединения",14);addView(status);
        summary=label("",14);addView(summary);enabled();
    }
    private TextView label(String s,int size){TextView v=new TextView(getContext());v.setText(s);v.setTextColor(Color.WHITE);v.setTextSize(size);v.setTag(Float.valueOf(size));v.setPadding(8,8,8,8);return v;}
    private Button button(LinearLayout parent,String s,Runnable r){Button b=new Button(getContext());b.setText(s);b.setTextSize(14);b.setTag(Float.valueOf(14));b.setFilterTouchesWhenObscured(true);b.setOnClickListener(v->r.run());parent.addView(b);return b;}
    private LinearLayout range(int i){
        LinearLayout box=new LinearLayout(getContext());box.setOrientation(VERTICAL);box.addView(label("Диапазон "+(i+1),17));
        price[i]=field("Точная цена первого триггера","");box.addView(price[i]);
        volume[i]=field("Начальный объём по шкале, лоты","0.01");volume[i].setEnabled(false);box.addView(volume[i]);
        side[i]=new Spinner(getContext());side[i].setAdapter(new ArrayAdapter<String>(getContext(),android.R.layout.simple_spinner_dropdown_item,new String[]{"BUY","SELL"}));side[i].setSelection(i);box.addView(side[i]);return box;
    }
    private EditText field(String hint,String value){EditText v=new EditText(getContext());v.setHint(hint);v.setText(value);v.setTextColor(Color.WHITE);v.setHintTextColor(Color.LTGRAY);v.setSingleLine();v.setTextSize(16);v.setTag(Float.valueOf(16));v.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_FLAG_DECIMAL);v.setFilterTouchesWhenObscured(true);return v;}
    private void secondVisibility(){second.setVisibility(two?VISIBLE:GONE);}
    private double positive(EditText v){double n=Double.parseDouble(v.getText().toString().trim().replace(',','.'));if(!Double.isFinite(n)||n<=0)throw new IllegalArgumentException();return n;}
    private void placeRanges(){
        RecoveryDistances distances;
        try{distances=new RecoveryDistances(initialSl.getText().toString(),reentry.getText().toString());}
        catch(IllegalArgumentException e){status.setText("Исходный SL: минимум 0,60. Повторный триггер от SL поддержки: любое положительное значение. Например 0,70 и 0,40.");return;}
        try{
            JSONArray ranges=new JSONArray();for(int i=0;i<(two?2:1);i++)ranges.put(new JSONObject().put("id",String.valueOf(i+1)).put("price",positive(price[i])).put("volume",positive(volume[i])).put("side",side[i].getSelectedItem().toString()));
            command("/api/recovery/ranges",new JSONObject().put("ranges",ranges)
                .put("initial_sl_distance",Double.parseDouble(distances.initialSl))
                .put("reentry_distance",Double.parseDouble(distances.supportReentry)));
        }catch(Exception e){status.setText("Введи положительные цену и объём для каждого выбранного диапазона.");}
    }
    private void command(String path,JSONObject body){
        if(!valid||busy||pending.contains("payload"))return;
        try{body.put("request_id",UUID.randomUUID().toString());
            final Api confirmedApi=new Api(getContext());
            if(nativeState!=null){JSONObject snapshot=nativeState.copy().getJSONObject("snapshot");body.put("expected_context",snapshot.getString("context_id")).put("expected_generation",snapshot.get("generation"));}
            android.app.AlertDialog confirm=new android.app.AlertDialog.Builder(getContext()).setTitle(nativeState==null?"Команда симуляции":"Подтвердить торговую команду")
                .setMessage((path.endsWith("/ranges")?"Выставить новые диапазоны":path.endsWith("/cancel")?"Отменить диапазоны":"Закрыть позицию и отменить диапазон №"+(path.contains("/1/")?"1":"2"))+"\nСервер: "+confirmedApi.baseUrl()+"\nСчёт: "+(nativeState==null?"симуляция":nativeState.accountTradeMode)+"\n"+body.toString())
                .setNegativeButton("Назад",null).setPositiveButton("Подтвердить",(dialog,which)->fetch(path,body,confirmedApi)).create();
            if(!(getContext() instanceof android.app.Activity))confirm.getWindow().setType(android.view.WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY);
            confirm.show();
            confirm.getButton(android.app.AlertDialog.BUTTON_POSITIVE).setFilterTouchesWhenObscured(true);
            confirm.getButton(android.app.AlertDialog.BUTTON_NEGATIVE).setFilterTouchesWhenObscured(true);
        }catch(Exception e){status.setText("Не удалось подготовить запрос. Проверь сохранённое соединение.");}
    }
    private static boolean simulation(JSONObject s){return "simulation".equals(s.optString("mode"))&&s.has("live_trading")&&!s.optBoolean("live_trading",true);}
    private static JSONObject unwrap(JSONObject result){JSONObject s=result.optJSONObject("state");return s==null?result:s;}
    private boolean allowed(NativeWidgetState n,String path){
        if(path.endsWith("/ranges"))return n.setRanges;
        if(path.endsWith("/cancel"))return n.cancelRanges;
        return n.closeCancelRangeIds.contains(path.contains("/ranges/1/")?"1":"2");
    }
    private void fetch(String path,JSONObject body){fetch(path,body,null);}
    private void clearPending(String expected) throws Exception {
        if(!expected.equals(pending.getString("payload",null)))throw new IllegalStateException("Изменился журнал команды; нужна сверка.");
        if(!pending.edit().clear().commit())throw new IllegalStateException("Не удалось сохранить подтверждение команды.");
    }
    private String resolvePending(Api api,NativeWidgetState parsed) throws Exception {
        if(parsed==null||!pending.contains("payload")||!api.baseUrl().equals(pending.getString("url",null)))return null;
        String saved=pending.getString("payload",null);JSONObject command=new JSONObject(saved);
        if(pending.contains("rejection_proof")){
            JSONObject proof=new JSONObject(pending.getString("rejection_proof",""));
            if(NativeDefiniteRejection.matches(proof.getJSONObject("response"),proof.getInt("http_status"),pending.getString("path",""),saved,pending.getInt("attempt_count",0))){
                clearPending(saved);return "rejected";
            }
        }
        String context=command.optString("expected_context","");
        if(context.isEmpty()||!context.equals(parsed.copy().getJSONObject("snapshot").getString("context_id")))return null;
        String id=command.getString("request_id");UUID.fromString(id);
        JSONObject reply=api.request("/api/recovery/commands/"+id,null);
        String outcome=NativePendingResolution.resolved(reply,pending.getString("path",""),command,context);
        if(outcome!=null)clearPending(saved);
        return outcome;
    }
    private void fetch(String path,JSONObject body,Api confirmedApi){
        if(disposed||busy)return;
        if(path!=null&&pending.contains("payload")){status.setText("Исход предыдущей команды не подтверждён. Новые команды не отправляются.");return;}
        main.removeCallbacks(poll);busy=true;valid=false;enabled();status.setText(path==null?"Проверяю состояние…":"Проверяю возможность команды…");
        worker.execute(()->{synchronized(DISPATCH_LOCK){try{
            if(disposed)return;
            Api api=confirmedApi==null?new Api(getContext()):confirmedApi;
            JSONObject envelope=unwrap(api.request("/api/recovery/state",null));
            boolean sim=simulation(envelope);
            NativeWidgetState parsed=sim?null:NativeWidgetState.parse(envelope,System.currentTimeMillis());
            String recovered=path==null?resolvePending(api,parsed):null;
            if(path!=null){
                if(disposed)throw new IllegalStateException("Панель остановлена до отправки команды.");
                if(pending.contains("payload"))throw new IllegalStateException("Другая команда ожидает сверки.");
                if(!api.sameConfiguration(getContext()))throw new IllegalStateException("Настройки соединения изменились. Подтверди действие заново.");
                if(body.has("expected_context")){
                    if(parsed==null)throw new IllegalStateException("Режим сервера изменился.");
                    JSONObject snap=parsed.copy().getJSONObject("snapshot");
                    if(!body.getString("expected_context").equals(snap.getString("context_id"))||!body.get("expected_generation").equals(snap.get("generation")))throw new IllegalStateException("Счёт или диапазоны изменились. Подтверди действие заново.");
                }else if(!sim)throw new IllegalStateException("Режим сервера изменился.");
                if(parsed!=null&&!allowed(parsed,path))throw new IllegalStateException("Сервер не разрешает это действие в текущем состоянии.");
                if(sim&&(path.endsWith("close-cancel")||!envelope.optBoolean("can_cancel_ranges",false)))throw new IllegalStateException("Команда симуляции недоступна.");
                String saved=body.toString(),requestId=body.getString("request_id");
                if(attempted.contains(requestId))throw new IllegalStateException("Этот идентификатор уже использован. Повторная отправка запрещена.");
                if(!attempted.edit().putBoolean(requestId,true).commit())throw new IllegalStateException("Не удалось сохранить защиту от повторной отправки.");
                if(!pending.edit().putString("payload",saved).putString("path",path).putString("url",api.baseUrl()).putInt("attempt_count",1).commit())throw new IllegalStateException("Не удалось сохранить идентификатор команды. Отправка отменена.");
                if(disposed){clearPending(saved);throw new IllegalStateException("Панель остановлена до отправки команды.");}
                JSONObject reply;
                try {reply=api.request(path,body);}
                catch(Api.DefiniteRejection rejected){
                    if(pending.getInt("attempt_count",0)!=1)throw new IllegalStateException("Отказ относится к одной попытке; нужна сверка остальных.");
                    if(!saved.equals(pending.getString("payload",null)))throw new IllegalStateException("Изменился журнал команды; нужна сверка.");
                    if(!pending.edit().putString("rejection_proof",rejected.proof.toString()).commit())throw new IllegalStateException("Отказ получен, но не удалось сохранить подтверждение. Не повторяй команду.");
                    clearPending(saved);
                    throw new IllegalStateException(rejected.getMessage());
                }
                if(!sim&&!NativeCommandReceipt.confirmed(reply,body.getString("request_id")))
                    throw new IllegalStateException("Сервер не подтвердил исход команды. Нужна сверка, не повторяй её.");
                clearPending(saved);
                envelope=unwrap(api.request("/api/recovery/state",null));
                if(sim!=simulation(envelope))throw new IllegalStateException("Сервер сменил режим. Обнови состояние.");
                parsed=sim?null:NativeWidgetState.parse(envelope,System.currentTimeMillis());
            }
            final String resolved=recovered;final NativeWidgetState next=parsed;final JSONObject result=sim?envelope:parsed.copy();
            main.post(()->{if(disposed)return;busy=false;valid=true;nativeState=next;state=result;render();
                status.setText(pending.contains("payload")?"Исход предыдущей команды неизвестен. Обновление проверяет журнал VPS и не повторяет команду.":"rejected".equals(resolved)?"Сервер подтвердил отклонение предыдущей команды. Можно изменить параметры и подтвердить новую.":"confirmed".equals(resolved)?"Результат предыдущей команды подтверждён журналом VPS.":next==null?"Симуляция подключена. Реальной торговли нет.":!next.fresh?"Нет свежего подтверждённого состояния MT5. Команды недоступны.":"MT5 подключён. Счёт: "+next.accountTradeMode+(path==null?"":". Ответ на команду получен; состояние обновлено."));
                enabled();schedule();});
        }catch(Exception e){main.post(()->{if(disposed)return;busy=false;valid=false;
            if(!summary.getText().toString().startsWith("УСТАРЕВШИЕ"))summary.setText("УСТАРЕВШИЕ ДАННЫЕ • связь не подтверждена\n"+summary.getText());
            status.setText(pending.contains("payload")?"Исход команды неизвестен. Нажми обновление для проверки журнала VPS; повторной отправки не будет.":e instanceof IllegalStateException?e.getMessage():"Нет подтверждённой связи с RECOVERY-сервером или несовместимый ответ. Проверь HTTPS, ключ и версию сервера.");
            enabled();if(path==null)schedule();});}}});
    }
    private void schedule(){if(active&&!disposed)main.postDelayed(poll,5000);}
    void setActive(boolean value){active=value;main.removeCallbacks(poll);if(value)fetch(null,null);}
    void dispose(){disposed=true;main.removeCallbacksAndMessages(null);worker.shutdown();}
    void setScale(float scale){scaleChildren(this,scale);}
    private void scaleChildren(View v,float scale){if(v instanceof TextView&&v.getTag() instanceof Float)((TextView)v).setTextSize(((Float)v.getTag())*scale);if(v instanceof ViewGroup){ViewGroup g=(ViewGroup)v;for(int i=0;i<g.getChildCount();i++)scaleChildren(g.getChildAt(i),scale);}}
    private void enabled(){
        boolean ready=valid&&!busy&&!pending.contains("payload");
        place.setEnabled(ready&&(nativeState!=null?nativeState.setRanges:state!=null&&state.optBoolean("can_cancel_ranges",false)));
        cancel.setEnabled(ready&&(nativeState!=null?nativeState.cancelRanges:state!=null&&state.optBoolean("can_cancel_ranges",false)));
        close1.setEnabled(ready&&nativeState!=null&&nativeState.closeCancelRangeIds.contains("1"));
        close2.setEnabled(ready&&nativeState!=null&&nativeState.closeCancelRangeIds.contains("2"));refresh.setEnabled(!busy);
    }
    private void render(){
        JSONObject settings=state.optJSONObject("settings");
        if(!distancesLoaded&&settings!=null){
            if(!distancesEdited){initialSl.setText(settings.optString("initial_sl_distance",RecoveryDistances.DEFAULT));reentry.setText(settings.optString("reentry_distance",RecoveryDistances.DEFAULT));distancesEdited=false;}
            distancesLoaded=true;
        }
        StringBuilder b=new StringBuilder(nativeState==null?"Состояние VPS (демо)\n":"Состояние MT5 • "+nativeState.accountTradeMode+"\n");
        if(settings!=null)b.append("Настройки сервера: SL ").append(settings.optString("initial_sl_distance"))
            .append(" · повторный триггер ").append(settings.optString("reentry_distance")).append("\n");
        JSONArray ranges=state.optJSONArray("ranges");
        if(ranges==null||ranges.length()==0)b.append("Нет диапазонов. Ожидание.\n");
        else for(int i=0;i<ranges.length();i++){JSONObject r=ranges.optJSONObject(i);if(r==null)continue;
            b.append("\nДиапазон №").append(r.optString("id")).append(" · ").append(r.optString("side")).append(" · ").append(r.optString("price"))
                .append("\nSL: ").append(r.optString("initial_sl_distance","—")).append(" · повтор: ").append(r.optString("reentry_distance","—"))
                .append("\nНачальный объём: ").append(r.optString("volume")).append("\n");
            JSONObject totals=state.optJSONObject("totals");JSONObject t=totals==null?null:totals.optJSONObject(r.optString("id"));
            if(nativeState!=null){b.append("Убытки закрытых позиций: ").append(t==null?"0":t.optString("gross_negative_closed_net","—"))
                .append(" · итог: ").append(t==null?"0":t.optString("realized_net","—"))
                .append(" · полных SL: ").append(t==null?"0":t.optString("full_sl_count","—")).append("\n");}
            else b.append("Убытки: ").append(r.optString("loss")).append(" · итог: ").append(r.optString("realized_net")).append("\n");}
        for(String key:new String[]{"positions","orders","loss_history"}){b.append("\n").append(key.equals("positions")?"Позиции":key.equals("orders")?"Триггеры":"История убытков").append(":\n");JSONArray a=state.optJSONArray(key);if(a==null)b.append("Данные не подтверждены\n");else if(a.length()==0)b.append("Нет\n");else for(int i=0;i<Math.min(a.length(),30);i++)b.append(a.opt(i)).append("\n");}
        summary.setText(b.toString());
    }
}
