package com.mihail.mt5panel;
import org.json.*;
public class NativeCommandReceiptTest {
    static int n;static void check(boolean b){n++;if(!b)throw new AssertionError(n);}
    public static void main(String[] args)throws Exception{
        JSONObject c=new JSONObject().put("request_id","abc").put("phase","completed").put("outcome","confirmed");
        JSONObject response=new JSONObject().put("command",c);
        check(NativeCommandReceipt.confirmed(response,"abc"));check(!NativeCommandReceipt.confirmed(response,"other"));
        check(!NativeCommandReceipt.confirmed(new JSONObject(),"abc"));
        c.put("outcome","reconciliation_required");check(!NativeCommandReceipt.confirmed(response,"abc"));
        c.remove("outcome");check(!NativeCommandReceipt.confirmed(response,"abc"));
        c.put("outcome","confirmed").put("phase","dispatching");check(!NativeCommandReceipt.confirmed(response,"abc"));
        c.put("phase","completed").put("request_id",123);check(!NativeCommandReceipt.confirmed(response,"123"));
        System.out.println("NativeCommandReceiptTest passed: "+n);
    }
}
