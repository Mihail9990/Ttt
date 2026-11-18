package com.mihail.mt5panel;

import android.app.Activity;
import android.os.Bundle;
import android.os.Build;
import android.content.Intent;
import android.net.Uri;
import android.provider.Settings;
import android.graphics.Color;
import android.widget.*;
import android.text.InputType;

public class MainActivity extends Activity {
    TextView status;
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        LinearLayout box=new LinearLayout(this);box.setOrientation(LinearLayout.VERTICAL);box.setPadding(24,60,24,24);box.setBackgroundColor(Color.rgb(17,21,27));
        ScrollView scroll=new ScrollView(this);scroll.addView(box);setContentView(scroll);
        TextView title=new TextView(this);title.setText("MT5 • Боковая панель");title.setTextSize(24);box.addView(title);
        TextView help=new TextView(this);help.setText("Панель RECOVERY поверх Bybit. Режим счёта подтверждается сервером. Native-режим может отправлять реальные торговые команды.\n\nВыбери один или два диапазона, укажи точные цены и направления первичных триггеров.\n\nСвёрнутый значок: свайп внутрь экрана открывает панель, обратный свайп по заголовку закрывает. Удерживай значок и перетащи к левому, правому или нижнему краю.\n\nДля соединения нужны HTTPS и ключ VPS-сервиса.");box.addView(help);
        addSizeControls(box);
        EditText url=new EditText(this);url.setHint("https://your-server.example");url.setSingleLine();url.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_URI);url.setText(SecureConfig.url(this));box.addView(url);
        EditText token=new EditText(this);token.setHint("Ключ доступа (оставь пустым, если сохранён)");token.setSingleLine();token.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_PASSWORD);box.addView(token);
        button(box,"Сохранить соединение",()->{try{String secret=token.getText().toString().trim();if(secret.isEmpty())secret=SecureConfig.token(this);SecureConfig.save(this,url.getText().toString(),secret);token.setText("");status.setText("Сохранено. При смене настроек останови и заново включи панель.");}catch(Exception e){status.setText(e instanceof IllegalArgumentException?e.getMessage():"Не удалось сохранить: введи корректный адрес и ключ заново");}});
        button(box,"Разрешить поверх приложений",()->startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,Uri.parse("package:"+getPackageName()))));
        button(box,"Включить панель",()->{
            if(!Settings.canDrawOverlays(this)){status.setText("Сначала разреши показ поверх приложений");return;}
            if(Build.VERSION.SDK_INT>=33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED)requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS},7);
            startForegroundService(new Intent(this,PanelService.class));status.setText("Панель включена. Удерживай значок для перемещения; свайп от края открывает.");
        });
        button(box,"Остановить панель",()->{stopService(new Intent(this,PanelService.class));status.setText("Панель остановлена. VPS продолжает работу. Уже отправленная команда может исполниться; остановка панели её не отменяет.");});
        status=new TextView(this);status.setText("Перед действием проверь сервер, режим счёта и параметры. Остановка панели не останавливает стратегию на VPS.");box.addView(status);
    }
    private void addSizeControls(LinearLayout box){
        TextView heading=new TextView(this);heading.setText("Размер панели");heading.setTextSize(20);box.addView(heading);
        TextView hint=new TextView(this);hint.setText("Ширина и высота относительно доступного экрана. Настройки сохраняются автоматически и сразу меняют открытую панель. Введённые цены диапазонов не сбрасываются. На маленьком экране действует минимальный читаемый размер; содержимое прокручивается.");box.addView(hint);
        TextView widthLabel=new TextView(this),heightLabel=new TextView(this);
        SeekBar width=new SeekBar(this),height=new SeekBar(this);
        width.setMax(PanelSizeRules.MAX_WIDTH_PERCENT-PanelSizeRules.MIN_WIDTH_PERCENT);
        height.setMax(PanelSizeRules.MAX_HEIGHT_PERCENT-PanelSizeRules.MIN_HEIGHT_PERCENT);
        width.setProgress(PanelSizePreferences.width(this)-PanelSizeRules.MIN_WIDTH_PERCENT);
        height.setProgress(PanelSizePreferences.height(this)-PanelSizeRules.MIN_HEIGHT_PERCENT);
        width.setContentDescription("Ширина боковой панели");height.setContentDescription("Высота боковой панели");
        width.setFilterTouchesWhenObscured(true);height.setFilterTouchesWhenObscured(true);
        Runnable labels=()->{widthLabel.setText("Ширина: "+(width.getProgress()+PanelSizeRules.MIN_WIDTH_PERCENT)+" %");heightLabel.setText("Высота: "+(height.getProgress()+PanelSizeRules.MIN_HEIGHT_PERCENT)+" %");};
        labels.run();box.addView(widthLabel);box.addView(width);box.addView(heightLabel);box.addView(height);
        SeekBar.OnSeekBarChangeListener listener=new SeekBar.OnSeekBarChangeListener(){
            public void onProgressChanged(SeekBar b,int value,boolean fromUser){labels.run();if(fromUser)PanelSizePreferences.save(MainActivity.this,width.getProgress()+PanelSizeRules.MIN_WIDTH_PERCENT,height.getProgress()+PanelSizeRules.MIN_HEIGHT_PERCENT);}
            public void onStartTrackingTouch(SeekBar b){}
            public void onStopTrackingTouch(SeekBar b){}
        };
        width.setOnSeekBarChangeListener(listener);height.setOnSeekBarChangeListener(listener);
        TextView scaleLabel=new TextView(this);SeekBar scale=new SeekBar(this);scale.setMax(75);
        scale.setProgress(PanelDockRules.scale(PanelSizePreferences.prefs(this).getInt("ui_scale",100))-75);
        scaleLabel.setText("Масштаб текста и значка: "+(scale.getProgress()+75)+" %");box.addView(scaleLabel);box.addView(scale);
        scale.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onProgressChanged(SeekBar b,int v,boolean user){scaleLabel.setText("Масштаб текста и значка: "+(v+75)+" %");if(user)PanelSizePreferences.prefs(MainActivity.this).edit().putInt("ui_scale",v+75).apply();}
            public void onStartTrackingTouch(SeekBar b){} public void onStopTrackingTouch(SeekBar b){}
        });
        button(box,"Стандартный размер",()->{width.setProgress(PanelSizeRules.DEFAULT_WIDTH_PERCENT-PanelSizeRules.MIN_WIDTH_PERCENT);height.setProgress(PanelSizeRules.DEFAULT_HEIGHT_PERCENT-PanelSizeRules.MIN_HEIGHT_PERCENT);PanelSizePreferences.save(this,PanelSizeRules.DEFAULT_WIDTH_PERCENT,PanelSizeRules.DEFAULT_HEIGHT_PERCENT);labels.run();});
    }
    void button(LinearLayout box,String label,Runnable run){Button b=new Button(this);b.setText(label);b.setFilterTouchesWhenObscured(true);b.setOnClickListener(v->run.run());box.addView(b);}
}
