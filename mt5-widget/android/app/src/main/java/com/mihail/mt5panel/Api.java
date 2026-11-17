package com.mihail.mt5panel;

import android.content.Context;
import org.json.JSONObject;
import javax.net.ssl.HttpsURLConnection;
import java.net.URL;
import java.io.InputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;

final class Api {
    private final String url,token;
    Api(Context c) throws Exception {url=SecureConfig.validateUrl(SecureConfig.url(c));token=SecureConfig.token(c);}
    JSONObject request(String path,JSONObject body) throws Exception {
        HttpsURLConnection c=(HttpsURLConnection)new URL(url+path).openConnection();
        c.setConnectTimeout(7000); c.setReadTimeout(12000); c.setInstanceFollowRedirects(false);
        c.setRequestProperty("Authorization","Bearer "+token); c.setRequestProperty("Accept","application/json");
        try {
            if(body!=null){c.setRequestMethod("POST");c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json");try(var out=c.getOutputStream()){out.write(body.toString().getBytes(StandardCharsets.UTF_8));}}
            int status=c.getResponseCode();
            if(status>=300 && status<400) throw new Exception("Перенаправление сервера отклонено");
            InputStream stream=status>=400?c.getErrorStream():c.getInputStream();
            if(stream==null)throw new Exception("Сервер вернул HTTP "+status);
            String text;
            try(stream;var out=new ByteArrayOutputStream()) {byte[] buf=new byte[4096];int n;while((n=stream.read(buf))!=-1){out.write(buf,0,n);if(out.size()>1_000_000)throw new Exception("Слишком большой ответ сервера");}text=out.toString("UTF-8");}
            if(status>=400){
                if(status==401 || status==403)throw new Exception("Доступ запрещён. Проверь ключ и разрешения сервера");
                throw new Exception("Ошибка сервера HTTP "+status+". Обнови позиции перед повторной попыткой");
            }
            return new JSONObject(text);
        } finally {c.disconnect();}
    }
}
