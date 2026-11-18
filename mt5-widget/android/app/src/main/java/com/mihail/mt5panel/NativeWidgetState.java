package com.mihail.mt5panel;

import org.json.*;
import java.time.Instant;
import java.util.*;

/** Strict, read-only native wire contract and fail-closed command capability gate. */
final class NativeWidgetState {
    final boolean fresh, setRanges, cancelRanges;
    final String accountTradeMode;
    final Set<String> closeCancelRangeIds;
    private final String serialized;

    static NativeWidgetState parse(JSONObject envelope, long nowMillis) throws JSONException {
        return new NativeWidgetState(object(envelope,"widget"), nowMillis);
    }
    private NativeWidgetState(JSONObject w, long now) throws JSONException {
        Object version=w.get("schema_version");
        if(!(version instanceof Integer)||((Integer)version)!=1)fail("schema_version");
        if(!"native".equals(string(w,"mode")))fail("mode");
        accountTradeMode=string(w,"account_trade_mode");
        if(!Arrays.asList("real","demo","contest","unknown").contains(accountTradeMode))fail("account_trade_mode");
        JSONObject snapshot=object(w,"snapshot");
        String status=string(snapshot,"status");
        if(!status.equals("fresh")&&!status.equals("unavailable"))fail("snapshot.status");
        string(snapshot,"symbol"); string(snapshot,"context_id");
        if(!snapshot.has("generation")||(!snapshot.isNull("generation")&&!(snapshot.get("generation") instanceof String)))fail("generation");
        long age=Long.MAX_VALUE;
        if(status.equals("fresh")) {
            try {long observed=Instant.parse(string(snapshot,"observed_at")).toEpochMilli();age=Math.subtractExact(now,observed);}
            catch(Exception e){throw new JSONException("Invalid snapshot time");}
        }
        // Clock skew or excessive age never authorizes actions. Re-fetch after clock repair.
        fresh=status.equals("fresh")&&age>=0&&age<=15000;
        object(w,"settings"); objects(w,"ranges"); objects(w,"loss_history"); object(w,"totals");
        if(status.equals("fresh")){objects(w,"positions");objects(w,"orders");}
        else if(!w.has("positions")||!w.isNull("positions")||!w.has("orders")||!w.isNull("orders"))fail("unavailable inventory must be null");
        boolean ready=bool(w,"executor_ready"), reconciliation=bool(w,"reconciliation_required");
        array(w,"issues");
        JSONObject cap=object(w,"capabilities");
        boolean set=bool(cap,"set_ranges"),cancel=bool(cap,"cancel_ranges");
        JSONArray ids=array(cap,"close_cancel_range_ids");
        Set<String> ranges=new HashSet<>(), closable=new HashSet<>();
        JSONArray configured=array(w,"ranges");
        for(int i=0;i<configured.length();i++){
            String id=string(configured.getJSONObject(i),"id");
            if(!Arrays.asList("1","2").contains(id)||!ranges.add(id))fail("range id");
        }
        for(int i=0;i<ids.length();i++){
            Object id=ids.get(i);
            if(!(id instanceof String)||!ranges.contains(id)||!closable.add((String)id))fail("close range id");
        }
        // Waiting generation may permit setRanges while executor_ready is false.
        // That exception is explicit; cancel/close never inherit it.
        setRanges=fresh&&!reconciliation&&set;
        cancelRanges=fresh&&!reconciliation&&ready&&cancel;
        closeCancelRangeIds=Collections.unmodifiableSet(fresh&&!reconciliation&&ready?closable:Collections.emptySet());
        if(fresh&&array(w,"positions").length()>0&&(set||cancel))fail("flat-only capability with position");
        serialized=w.toString();
    }
    JSONObject copy() throws JSONException {return new JSONObject(serialized);}
    private static void fail(String field)throws JSONException{throw new JSONException("Invalid native widget state: "+field);}
    private static JSONObject object(JSONObject o,String k)throws JSONException{Object v=o.get(k);if(!(v instanceof JSONObject))fail(k);return (JSONObject)v;}
    private static JSONArray array(JSONObject o,String k)throws JSONException{Object v=o.get(k);if(!(v instanceof JSONArray))fail(k);return (JSONArray)v;}
    private static void objects(JSONObject o,String k)throws JSONException{JSONArray a=array(o,k);for(int i=0;i<a.length();i++)if(!(a.get(i) instanceof JSONObject))fail(k);}
    private static String string(JSONObject o,String k)throws JSONException{Object v=o.get(k);if(!(v instanceof String)||((String)v).isEmpty())fail(k);return (String)v;}
    private static boolean bool(JSONObject o,String k)throws JSONException{Object v=o.get(k);if(!(v instanceof Boolean))fail(k);return (Boolean)v;}
}
