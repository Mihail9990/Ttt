package com.mihail.mt5panel;
import org.json.*;
/** Only a matching persisted and confirmed receipt resolves a locally pending POST. */
final class NativeCommandReceipt {
    static boolean confirmed(JSONObject response,String requestId) throws JSONException {
        JSONObject c=response.optJSONObject("command");
        return c!=null&&requestId!=null&&!requestId.isEmpty()
            &&requestId.equals(c.opt("request_id"))
            &&"completed".equals(c.opt("phase"))&&"confirmed".equals(c.opt("outcome"));
    }
}
