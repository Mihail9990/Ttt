package com.mihail.mt5panel;
import org.json.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
/** Typed server proof for this single HTTP attempt, never inferred from 401/422 alone. */
final class NativeDefiniteRejection {
    static boolean matches(JSONObject response,int status,String path,String rawBody,int attempts) {
        try {
            if(attempts!=1||(status!=401&&status!=422)||rawBody==null)return false;
            JSONObject r=response.getJSONObject("rejection"), body=new JSONObject(rawBody);
            if(!(r.get("schema_version") instanceof Integer)||r.getInt("schema_version")!=1)return false;
            String reason=status==401?"authentication_failed":"validation_failed";
            return "attempt_only".equals(r.get("scope"))&&Boolean.TRUE.equals(r.get("attempt_only"))&&"POST".equals(r.get("method"))&&path.equals(r.get("path"))
                &&body.getString("request_id").equals(r.get("request_id"))
                &&"not_dispatched".equals(r.get("phase"))&&reason.equals(r.get("reason"))
                &&digest(rawBody).equals(r.get("request_sha256"));
        }catch(Exception e){return false;}
    }
    static String digest(String body)throws Exception {
        byte[] bytes=MessageDigest.getInstance("SHA-256").digest(body.getBytes(StandardCharsets.UTF_8));
        StringBuilder h=new StringBuilder();for(byte b:bytes)h.append(String.format(java.util.Locale.ROOT,"%02x",b&255));return h.toString();
    }
}
