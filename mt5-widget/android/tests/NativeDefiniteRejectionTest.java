package com.mihail.mt5panel;
import org.json.*;
public class NativeDefiniteRejectionTest {
    static int n;static void check(boolean b){n++;if(!b)throw new AssertionError(n);}
    public static void main(String[] args)throws Exception{
        String body="{\"request_id\":\"abc\",\"expected_context\":\"bound\"}",path="/api/recovery/ranges";
        JSONObject r=new JSONObject().put("schema_version",1).put("method","POST").put("path",path).put("request_id","abc").put("request_sha256",NativeDefiniteRejection.digest(body)).put("phase","not_dispatched").put("reason","authentication_failed").put("attempt_only",true).put("scope","attempt_only");
        JSONObject response=new JSONObject().put("rejection",r);
        check(NativeDefiniteRejection.matches(response,401,path,body,1));
        check(!NativeDefiniteRejection.matches(response,401,path,body,2));
        check(!NativeDefiniteRejection.matches(response,401,path,body,0));
        check(!NativeDefiniteRejection.matches(response,401,"/other",body,1));
        check(!NativeDefiniteRejection.matches(response,401,path,body+" ",1));
        check(!NativeDefiniteRejection.matches(response,409,path,body,1));
        check(!NativeDefiniteRejection.matches(response,422,path,body,1));
        r.put("reason","validation_failed");check(NativeDefiniteRejection.matches(response,422,path,body,1));
        r.put("request_id","other");check(!NativeDefiniteRejection.matches(response,422,path,body,1));r.put("request_id","abc");
        r.put("attempt_only",false);check(!NativeDefiniteRejection.matches(response,422,path,body,1));r.put("attempt_only",true).put("scope","attempt_only");
        r.put("schema_version","1");check(!NativeDefiniteRejection.matches(response,422,path,body,1));
        check(!NativeDefiniteRejection.matches(new JSONObject(),401,path,body,1));
        System.out.println("NativeDefiniteRejectionTest passed: "+n);
    }
}
