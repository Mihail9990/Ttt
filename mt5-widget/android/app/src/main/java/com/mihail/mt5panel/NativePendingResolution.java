package com.mihail.mt5panel;
import org.json.*;
import java.math.BigDecimal;
import java.util.Iterator;
/** No sends. Only terminal, same-context, exact logical payload receipts resolve pending. */
final class NativePendingResolution {
    static String resolved(JSONObject response,String path,JSONObject body,String context)throws JSONException {
        if(!context.equals(response.opt("context_id")))return null;
        JSONObject c=response.optJSONObject("command");
        if(c==null||!body.getString("request_id").equals(c.opt("request_id")))return null;
        String phase=c.optString("phase"),outcome=c.optString("outcome");
        if(!((phase.equals("completed")&&(outcome.equals("confirmed")||(outcome.equals("partially_applied")&&"partially_applied".equals(NativeCommandReceipt.terminalOutcome(response,body.getString("request_id"))))))||(phase.equals("rejected")&&outcome.equals("rejected"))))return null;
        if(outcome.equals("partially_applied")&&!NativeCommandReceipt.partialMatchesRequest(c,body))return null;
        JSONObject expected=new JSONObject(body.toString());expected.remove("request_id");
        if(path.equals("/api/recovery/ranges"))expected.put("kind","ranges");
        else if(path.equals("/api/recovery/cancel"))expected.put("kind","cancel");
        else if(path.equals("/api/recovery/ranges/1/close-cancel")||path.equals("/api/recovery/ranges/2/close-cancel"))expected.put("kind","close_cancel").put("range_id",path.contains("/1/")?"1":"2");
        else return null;
        JSONObject payload=c.optJSONObject("payload");
        return payload!=null&&same(expected,payload,"")?outcome:null;
    }
    private static boolean same(Object a,Object b,String key)throws JSONException {
        if(a==JSONObject.NULL||b==JSONObject.NULL)return a==b;
        if(a instanceof JSONObject&&b instanceof JSONObject){JSONObject x=(JSONObject)a,y=(JSONObject)b;if(x.length()!=y.length())return false;Iterator<String> keys=x.keys();while(keys.hasNext()){String k=keys.next();if(!y.has(k)||!same(x.get(k),y.get(k),k))return false;}return true;}
        if(a instanceof JSONArray&&b instanceof JSONArray){JSONArray x=(JSONArray)a,y=(JSONArray)b;if(x.length()!=y.length())return false;for(int i=0;i<x.length();i++)if(!same(x.get(i),y.get(i),key))return false;return true;}
        if((a instanceof Number&&b instanceof Number)||key.equals("initial_sl_distance")||key.equals("reentry_distance")||key.equals("price")||key.equals("volume"))try{return new BigDecimal(a.toString()).compareTo(new BigDecimal(b.toString()))==0;}catch(Exception e){return false;}
        return a!=null&&a.equals(b);
    }
}
