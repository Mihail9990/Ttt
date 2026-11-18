package com.mihail.mt5panel;
import org.json.*;
public class NativeRejectedReceiptTest {
 static int n;static void check(boolean b){n++;if(!b)throw new AssertionError(n);}
 public static void main(String[] args)throws Exception {
  JSONObject body=new JSONObject().put("request_id","abc").put("ranges",new JSONArray().put(new JSONObject().put("id","1")).put(new JSONObject().put("id","2")));
  JSONArray rows=new JSONArray().put(new JSONObject().put("range_id","1").put("status","rejected")).put(new JSONObject().put("range_id","2").put("status","not_dispatched"));
  JSONObject c=new JSONObject().put("request_id","abc").put("phase","rejected").put("outcome","rejected").put("range_outcomes",rows),reply=new JSONObject().put("command",c);
  check(NativeCommandReceipt.rejectedRangeReceipt(reply,body));check(!NativeCommandReceipt.confirmed(reply,"abc"));
  rows.getJSONObject(1).put("status","rejected");check(NativeCommandReceipt.rejectedRangeReceipt(reply,body));
  c.put("request_id","wrong");check(!NativeCommandReceipt.rejectedRangeReceipt(reply,body));c.put("request_id","abc");
  c.put("phase","dispatching");check(!NativeCommandReceipt.rejectedRangeReceipt(reply,body));c.put("phase","rejected");
  c.put("outcome","reconciliation_required");check(!NativeCommandReceipt.rejectedRangeReceipt(reply,body));c.put("outcome","rejected");
  rows.getJSONObject(1).put("status","confirmed");check(!NativeCommandReceipt.rejectedRangeReceipt(reply,body));
  rows.getJSONObject(1).put("status","unknown");check(!NativeCommandReceipt.rejectedRangeReceipt(reply,body));
  rows.getJSONObject(1).put("status","rejected").put("range_id","1");check(!NativeCommandReceipt.rejectedRangeReceipt(reply,body));
  c.remove("range_outcomes");check(!NativeCommandReceipt.rejectedRangeReceipt(reply,body));
  check(!NativeCommandReceipt.rejectedRangeReceipt(new JSONObject(),body));
  System.out.println("NativeRejectedReceiptTest passed: "+n);
 }
}
