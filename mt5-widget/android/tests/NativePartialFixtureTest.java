package com.mihail.mt5panel;
import org.json.*;import java.nio.file.*;
public class NativePartialFixtureTest {
 public static void main(String[] args)throws Exception {
  JSONObject f=new JSONObject(Files.readString(Path.of(args[0])));Object raw=f.get("body");JSONObject body=raw instanceof JSONObject?(JSONObject)raw:new JSONObject((String)raw);
  JSONObject post=f.getJSONObject("post"),status=f.getJSONObject("status");String id=body.getString("request_id");
  if(!"partially_applied".equals(NativeCommandReceipt.terminalOutcome(post,id))||!NativeCommandReceipt.partialMatchesRequest(post.getJSONObject("command"),body))throw new AssertionError("POST partial receipt");
  if(!"partially_applied".equals(NativePendingResolution.resolved(status,f.getString("path"),body,body.getString("expected_context"))))throw new AssertionError("GET partial resolution");
  System.out.println("NativePartialFixtureTest passed: 2");
 }
}
