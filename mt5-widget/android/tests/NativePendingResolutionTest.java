package com.mihail.mt5panel;
import org.json.*;
public class NativePendingResolutionTest {
    static int n;static void check(boolean b){n++;if(!b)throw new AssertionError(n);}
    public static void main(String[] args)throws Exception {
        JSONObject body=new JSONObject().put("request_id","abc").put("expected_context","bound").put("expected_generation",JSONObject.NULL).put("initial_sl_distance",0.7).put("reentry_distance",0.4).put("ranges",new JSONArray().put(new JSONObject().put("id","1").put("side","BUY").put("price",4000).put("volume",0.01)));
        JSONObject payload=new JSONObject(body.toString());payload.remove("request_id");payload.put("kind","ranges").put("initial_sl_distance","0.70");
        JSONObject c=new JSONObject().put("request_id","abc").put("phase","completed").put("outcome","confirmed").put("payload",payload);
        JSONObject reply=new JSONObject().put("context_id","bound").put("command",c);
        String path="/api/recovery/ranges";
        check("confirmed".equals(NativePendingResolution.resolved(reply,path,body,"bound")));
        check(NativePendingResolution.resolved(reply,path,body,"other")==null);
        c.put("phase","rejected").put("outcome","rejected");check("rejected".equals(NativePendingResolution.resolved(reply,path,body,"bound")));
        for(String phase:new String[]{"not_recorded","dispatching","unknown"}){c.put("phase",phase);check(NativePendingResolution.resolved(reply,path,body,"bound")==null);}
        c.put("phase","completed").put("outcome","reconciliation_required");check(NativePendingResolution.resolved(reply,path,body,"bound")==null);
        c.put("outcome","confirmed");payload.put("expected_generation","other");check(NativePendingResolution.resolved(reply,path,body,"bound")==null);payload.put("expected_generation",JSONObject.NULL);
        payload.getJSONArray("ranges").getJSONObject(0).put("price",4001);check(NativePendingResolution.resolved(reply,path,body,"bound")==null);
        check(NativePendingResolution.resolved(reply,"/wrong",body,"bound")==null);
        // A reconcile response (state only, no original terminal receipt) never resolves a trade.
        check(NativePendingResolution.resolved(new JSONObject().put("context_id","bound").put("widget",new JSONObject()),path,body,"bound")==null);
        check(NativePendingResolution.resolved(reply,"/api/recovery/reconcile",body,"bound")==null);
        System.out.println("NativePendingResolutionTest passed: "+n);
    }
}
