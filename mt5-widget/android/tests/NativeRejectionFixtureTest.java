package com.mihail.mt5panel;
import java.nio.file.*;import org.json.*;
public class NativeRejectionFixtureTest {
    public static void main(String[] args)throws Exception{
        JSONArray cases=new JSONArray(Files.readString(Path.of(args[0])));
        for(int i=0;i<cases.length();i++){
            JSONObject c=cases.getJSONObject(i);
            if(!NativeDefiniteRejection.matches(c.getJSONObject("response"),c.getInt("status"),c.getString("path"),c.getString("body"),1))throw new AssertionError("actual server rejection "+i);
        }
        System.out.println("NativeRejectionFixtureTest passed: "+cases.length());
    }
}
