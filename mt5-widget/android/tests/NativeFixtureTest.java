package com.mihail.mt5panel;
import java.nio.file.*;import java.time.Instant;import org.json.*;
public class NativeFixtureTest {
 public static void main(String[] args)throws Exception {
  JSONObject response=new JSONObject(Files.readString(Path.of(args[0])));
  long now=Instant.parse(response.getJSONObject("widget").getJSONObject("snapshot").getString("observed_at")).toEpochMilli();
  NativeWidgetState s=NativeWidgetState.parse(response,now);
  if(!s.fresh||s.setRanges||s.cancelRanges)throw new AssertionError("Position must prevent flat-only operations");
  System.out.println("Native actual server fixture: PASS (fresh, flat-only actions disabled)");
 }
}
