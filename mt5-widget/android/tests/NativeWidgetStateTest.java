package com.mihail.mt5panel;
import org.json.*;
public class NativeWidgetStateTest {
    static int n;
    static final long NOW=1800000000000L;
    static JSONObject valid()throws Exception{return new JSONObject("{\"widget\":{\"schema_version\":1,\"mode\":\"native\",\"account_trade_mode\":\"demo\",\"snapshot\":{\"status\":\"fresh\",\"observed_at\":\"2027-01-15T08:00:00Z\",\"generation\":null,\"symbol\":\"XAUUSD\",\"context_id\":\"test-binding\"},\"settings\":{},\"ranges\":[{\"id\":\"1\"}],\"positions\":[],\"orders\":[],\"loss_history\":[],\"totals\":{},\"executor_ready\":true,\"reconciliation_required\":false,\"issues\":[],\"capabilities\":{\"set_ranges\":true,\"cancel_ranges\":true,\"close_cancel_range_ids\":[\"1\"]}}}");}
    static void check(boolean x){n++;if(!x)throw new AssertionError(n);}
    static void reject(JSONObject x)throws Exception{try{NativeWidgetState.parse(x,NOW);throw new AssertionError("accepted");}catch(JSONException expected){n++;}}
    public static void main(String[] args)throws Exception {
        JSONObject x=valid(), w=x.getJSONObject("widget");NativeWidgetState s=NativeWidgetState.parse(x,NOW);check(s.fresh&&s.setRanges&&s.cancelRanges&&s.accountTradeMode.equals("demo"));
        check(!NativeWidgetState.parse(x,NOW+15001).setRanges);check(!NativeWidgetState.parse(x,NOW-1).setRanges);
        w.put("reconciliation_required",true);check(!NativeWidgetState.parse(x,NOW).setRanges);w.put("reconciliation_required",false);
        w.put("executor_ready",false);s=NativeWidgetState.parse(x,NOW);check(s.setRanges&&!s.cancelRanges&&s.closeCancelRangeIds.isEmpty());
        x=valid();x.getJSONObject("widget").put("schema_version","1");reject(x);
        x=valid();x.getJSONObject("widget").remove("positions");reject(x);
        x=valid();x.getJSONObject("widget").put("positions",new JSONArray().put(new JSONObject()));reject(x);
        x=valid();x.getJSONObject("widget").getJSONObject("capabilities").put("set_ranges","true");reject(x);
        x=valid();x.getJSONObject("widget").getJSONObject("capabilities").put("close_cancel_range_ids",new JSONArray().put("2"));reject(x);
        x=valid();w=x.getJSONObject("widget");w.getJSONObject("snapshot").put("status","unavailable");w.put("positions",JSONObject.NULL).put("orders",JSONObject.NULL);s=NativeWidgetState.parse(x,NOW);check(!s.fresh&&!s.setRanges&&!s.cancelRanges);
        reject(new JSONObject());System.out.println("NativeWidgetStateTest passed: "+n);
    }
}
