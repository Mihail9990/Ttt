package com.mihail.mt5panel;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import java.security.KeyStore;
import java.net.URI;

final class SecureConfig {
    private static final String ALIAS="mt5-panel-token";
    private static SecretKey key() throws Exception {
        KeyStore ks=KeyStore.getInstance("AndroidKeyStore"); ks.load(null);
        if (!ks.containsAlias(ALIAS)) {
            KeyGenerator g=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
            g.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
            g.generateKey();
        }
        return (SecretKey)ks.getKey(ALIAS,null);
    }
    static String validateUrl(String value) {
        String s=value.trim().replaceAll("/+$", "");
        try { URI u=URI.create(s); if (!"https".equals(u.getScheme()) || u.getHost()==null || u.getUserInfo()!=null || u.getQuery()!=null || u.getFragment()!=null || !u.getPath().isEmpty()) throw new Exception(); }
        catch(Exception e){throw new IllegalArgumentException("Нужен HTTPS-адрес сервера без пути, логина и параметров");}
        return s;
    }
    static void save(Context c,String url,String token) throws Exception {
        url=validateUrl(url);
        if(token.length()<32 || token.contains("\n") || token.contains("\r")) throw new IllegalArgumentException("Ключ должен содержать минимум 32 символа");
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE,key());
        String encrypted=Base64.encodeToString(cipher.doFinal(token.getBytes(java.nio.charset.StandardCharsets.UTF_8)),Base64.NO_WRAP);
        if(!c.getSharedPreferences("connection",0).edit().putString("url",url).putString("token",encrypted).putString("iv",Base64.encodeToString(cipher.getIV(),Base64.NO_WRAP)).commit()) throw new Exception("Не удалось сохранить настройки");
    }
    static String url(Context c){return c.getSharedPreferences("connection",0).getString("url","");}
    static String token(Context c) throws Exception {
        var p=c.getSharedPreferences("connection",0); Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,Base64.decode(p.getString("iv",""),Base64.NO_WRAP)));
        return new String(cipher.doFinal(Base64.decode(p.getString("token",""),Base64.NO_WRAP)),java.nio.charset.StandardCharsets.UTF_8);
    }
}
