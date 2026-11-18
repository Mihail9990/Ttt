package com.mihail.mt5panel;

import android.content.Context;
import android.graphics.Color;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.View;
import android.view.ViewGroup;
import android.widget.*;
import org.json.*;
import java.util.UUID;
import java.util.concurrent.*;

/** Simulation-only RECOVERY controls. Never connects this prototype to live trading. */
final class RecoveryPanelView extends LinearLayout {
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final TextView status,summary;
    private final EditText[] price=new EditText[2],volume=new EditText[2];
    private final Spinner[] side=new Spinner[2];
    private final LinearLayout second;
    private final Button place,cancel,close1,close2,refresh;
    private boolean two,busy,valid,disposed,active;
    private JSONObject state;
    private final Runnable poll=()->{if(active&&!disposed)fetch(null,null);};
    RecoveryPanelView(Context c){
        super(c);setOrientation(VERTICAL);
        addView(label("RECOVERY • ТОЛЬКО СИМУЛЯЦИЯ",19));
        addView(label("Реальные ордера не отправляются. VPS-сервер RECOVERY должен быть отдельно настроен.",14));
        LinearLayout choices=new LinearLayout(c);
        button(choices,"1 диапазон",()->{two=false;secondVisibility();});
        button(choices,"2 диапазона",()->{two=true;secondVisibility();});addView(choices);
        addView(range(0));second=range(1);addView(second);second.setVisibility(GONE);
        place=button(this,"Подтвердить диапазоны (демо)",this::placeRanges);
        refresh=button(this,"Обновить состояние",()->fetch(null,null));
        cancel=button(this,"Отменить диапазоны и ждать",()->command("/api/recovery/cancel",new JSONObject()));
        close1=button(this,"Закрыть позицию и отменить №1",()->command("/api/recovery/ranges/1/close-cancel",new JSONObject()));
        close2=button(this,"Закрыть позицию и отменить №2",()->command("/api/recovery/ranges/2/close-cancel",new JSONObject()));
        addView(label("Закрытие позиции в этой симуляции пока недоступно: нужен подтверждённый результат сделки.",13));
        status=label("Нет подтверждённого соединения",14);addView(status);
        summary=label("",14);addView(summary);enabled();
    }
    private TextView label(String s,int size){TextView v=new TextView(getContext());v.setText(s);v.setTextColor(Color.WHITE);v.setTextSize(size);v.setTag(Float.valueOf(size));v.setPadding(8,8,8,8);return v;}
    private Button button(LinearLayout parent,String s,Runnable r){Button b=new Button(getContext());b.setText(s);b.setTextSize(14);b.setTag(Float.valueOf(14));b.setFilterTouchesWhenObscured(true);b.setOnClickListener(v->r.run());parent.addView(b);return b;}
    private LinearLayout range(int i){
        LinearLayout box=new LinearLayout(getContext());box.setOrientation(VERTICAL);box.addView(label("Диапазон "+(i+1),17));
        price[i]=field("Точная цена первого триггера","");box.addView(price[i]);
        volume[i]=field("Объём, лоты","0.01");box.addView(volume[i]);
        side[i]=new Spinner(getContext());side[i].setAdapter(new ArrayAdapter<String>(getContext(),android.R.layout.simple_spinner_dropdown_item,new String[]{"BUY","SELL"}));side[i].setSelection(i);box.addView(side[i]);return box;
    }
    private EditText field(String hint,String value){EditText v=new EditText(getContext());v.setHint(hint);v.setText(value);v.setTextColor(Color.WHITE);v.setHintTextColor(Color.LTGRAY);v.setSingleLine();v.setTextSize(16);v.setTag(Float.valueOf(16));v.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_FLAG_DECIMAL);v.setFilterTouchesWhenObscured(true);return v;}
    private void secondVisibility(){second.setVisibility(two?VISIBLE:GONE);}
    private double positive(EditText v){double n=Double.parseDouble(v.getText().toString().trim().replace(',','.'));if(!Double.isFinite(n)||n<=0)throw new IllegalArgumentException();return n;}
    private void placeRanges(){try{JSONArray ranges=new JSONArray();for(int i=0;i<(two?2:1);i++)ranges.put(new JSONObject().put("id",String.valueOf(i+1)).put("price",positive(price[i])).put("volume",positive(volume[i])).put("side",side[i].getSelectedItem().toString()));command("/api/recovery/ranges",new JSONObject().put("ranges",ranges));}catch(Exception e){status.setText("Введи положительные цену и объём для каждого выбранного диапазона.");}}
    private void command(String path,JSONObject body){if(!valid||busy)return;try{body.put("request_id",UUID.randomUUID().toString());fetch(path,body);}catch(JSONException e){status.setText("Не удалось подготовить запрос");}}
    private static boolean simulation(JSONObject s){return "simulation".equals(s.optString("mode"))&&s.has("live_trading")&&!s.optBoolean("live_trading",true);}
    private static JSONObject unwrap(JSONObject result){JSONObject s=result.optJSONObject("state");return s==null?result:s;}
    private void fetch(String path,JSONObject body){
        if(disposed||busy)return;main.removeCallbacks(poll);busy=true;valid=false;enabled();status.setText(path==null?"Проверяю состояние…":"Отправляю демо-команду…");
        worker.execute(()->{try{Api api=new Api(getContext());JSONObject s=unwrap(api.request("/api/recovery/state",null));if(!simulation(s))throw new IllegalStateException("Этот прототип поддерживает только simulation. Команды заблокированы.");if(path!=null){api.request(path,body);s=unwrap(api.request("/api/recovery/state",null));if(!simulation(s))throw new IllegalStateException("Сервер сменил режим. Команды заблокированы.");}final JSONObject result=s;main.post(()->{if(disposed)return;busy=false;valid=true;state=result;render();status.setText(path==null?"Симуляция подключена. Реальной торговли нет.":"Состояние симуляции обновлено.");enabled();schedule();});}catch(Exception e){main.post(()->{if(disposed)return;busy=false;valid=false;status.setText(e instanceof IllegalStateException?e.getMessage():(path==null?"Нет связи с RECOVERY-сервером. Проверь HTTPS и ключ.":"Результат команды не подтверждён. Обнови состояние перед повтором."));enabled();/* No blind automatic mutation retries. */if(path==null)schedule();});}});
    }
    private void schedule(){if(active&&!disposed)main.postDelayed(poll,5000);}
    void setActive(boolean value){active=value;main.removeCallbacks(poll);if(value)fetch(null,null);}
    void dispose(){disposed=true;main.removeCallbacksAndMessages(null);worker.shutdown();}
    void setScale(float scale){scaleChildren(this,scale);}
    private void scaleChildren(View v,float scale){if(v instanceof TextView&&v.getTag() instanceof Float)((TextView)v).setTextSize(((Float)v.getTag())*scale);if(v instanceof ViewGroup){ViewGroup g=(ViewGroup)v;for(int i=0;i<g.getChildCount();i++)scaleChildren(g.getChildAt(i),scale);}}
    private void enabled(){boolean ready=valid&&!busy;place.setEnabled(ready);refresh.setEnabled(!busy);cancel.setEnabled(ready&&state!=null&&state.optBoolean("can_cancel_ranges",false));close1.setEnabled(false);close2.setEnabled(false);}
    private void render(){
        StringBuilder b=new StringBuilder("Состояние VPS (демо)\n");
        JSONArray ranges=state.optJSONArray("ranges");
        if(ranges==null||ranges.length()==0)b.append("Нет диапазонов. Ожидание.\n");
        else for(int i=0;i<ranges.length();i++){JSONObject r=ranges.optJSONObject(i);if(r==null)continue;
            b.append("\nДиапазон №").append(r.optString("id")).append(" · ").append(r.optString("side")).append(" · ").append(r.optString("price"))
                .append("\nОбъём: ").append(r.optString("volume")).append("  Убытки: ").append(r.optString("loss"))
                .append("\nРезультат: ").append(r.optString("realized_net")).append("\n");}
        for(String key:new String[]{"positions","orders","loss_history"}){b.append("\n").append(key.equals("positions")?"Позиции":key.equals("orders")?"Триггеры":"История убытков").append(":\n");JSONArray a=state.optJSONArray(key);if(a==null||a.length()==0)b.append("Нет\n");else for(int i=0;i<Math.min(a.length(),30);i++)b.append(a.opt(i)).append("\n");}
        summary.setText(b.toString());
    }
}
