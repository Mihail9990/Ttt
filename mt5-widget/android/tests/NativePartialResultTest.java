package com.mihail.mt5panel;
import org.json.*;
public class NativePartialResultTest {
    static int n;static void check(boolean b){n++;if(!b)throw new AssertionError(n);}
    public static void main(String[] args)throws Exception {
        JSONObject c=new JSONObject().put("request_id","partial").put("phase","completed").put("outcome","partially_applied");
        JSONArray ranges=new JSONArray().put(new JSONObject().put("range_id","1").put("status","confirmed")).put(new JSONObject().put("range_id","2").put("status","not_dispatched"));
        c.put("range_outcomes",ranges);JSONObject reply=new JSONObject().put("command",c);
        check("partially_applied".equals(NativeCommandReceipt.terminalOutcome(reply,"partial")));
        check(!NativeCommandReceipt.confirmed(reply,"partial"));
        String message=NativeCommandReceipt.partialMessage(c);
        check(message.contains("Применено частично")&&message.contains("№1: первичная отправка подтверждена")&&message.contains("№2: не отправлен")&&message.contains("Автоматического повтора нет"));
        check(NativeCommandReceipt.terminalOutcome(reply,"other")==null);
        c.put("phase","dispatching");check(NativeCommandReceipt.terminalOutcome(reply,"partial")==null);c.put("phase","completed");
        ranges.getJSONObject(1).put("status","rejected");check(NativeCommandReceipt.partialMessage(c).contains("№2: отклонён"));
        ranges.getJSONObject(1).put("status","unknown");check(NativeCommandReceipt.terminalOutcome(reply,"partial")==null);
        ranges.getJSONObject(1).put("status","confirmed");check(NativeCommandReceipt.terminalOutcome(reply,"partial")==null);
        ranges.getJSONObject(1).put("status","not_dispatched").put("range_id","1");check(NativeCommandReceipt.terminalOutcome(reply,"partial")==null);
        ranges.getJSONObject(1).put("range_id","2");
        JSONObject body=new JSONObject().put("request_id","partial").put("expected_context","ctx").put("expected_generation",JSONObject.NULL).put("ranges",new JSONArray().put(new JSONObject().put("id","1")).put(new JSONObject().put("id","2")));
        check(NativeCommandReceipt.partialMatchesRequest(c,body));
        check(!NativeCommandReceipt.partialMatchesRequest(c,new JSONObject().put("ranges",new JSONArray())));
        JSONObject payload=new JSONObject(body.toString());payload.remove("request_id");payload.put("kind","ranges");c.put("payload",payload);reply.put("context_id","ctx");
        check("partially_applied".equals(NativePendingResolution.resolved(reply,"/api/recovery/ranges",body,"ctx")));
        payload.put("expected_generation","changed");check(NativePendingResolution.resolved(reply,"/api/recovery/ranges",body,"ctx")==null);
        ranges.getJSONObject(0).put("status","rejected");
        check(NativeCommandReceipt.terminalOutcome(reply,"partial")==null);
        ranges.getJSONObject(0).put("status","not_dispatched");
        check(NativeCommandReceipt.terminalOutcome(reply,"partial")==null);
        ranges.getJSONObject(1).put("status","rejected");
        check(NativeCommandReceipt.terminalOutcome(reply,"partial")==null);
        c.remove("range_outcomes");check(NativeCommandReceipt.terminalOutcome(reply,"partial")==null);
        System.out.println("NativePartialResultTest passed: "+n);
    }
}
