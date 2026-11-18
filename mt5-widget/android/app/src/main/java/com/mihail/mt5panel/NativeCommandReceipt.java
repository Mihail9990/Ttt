package com.mihail.mt5panel;
import org.json.*;
import java.util.HashSet;
/** A partial terminal result is distinct from complete success and never requests a retry. */
final class NativeCommandReceipt {
    static boolean confirmed(JSONObject response,String requestId) throws JSONException {
        return "confirmed".equals(terminalOutcome(response,requestId));
    }
    static String terminalOutcome(JSONObject response,String requestId)throws JSONException {
        JSONObject c=response.optJSONObject("command");
        if(c==null||requestId==null||requestId.isEmpty()||!requestId.equals(c.opt("request_id"))||!"completed".equals(c.opt("phase")))return null;
        if("confirmed".equals(c.opt("outcome")))return "confirmed";
        if("partially_applied".equals(c.opt("outcome"))&&partialMessage(c)!=null)return "partially_applied";
        return null;
    }
    static boolean rejectedRangeReceipt(JSONObject response,JSONObject body)throws JSONException {
        JSONObject c=response.optJSONObject("command");
        if(c==null||!body.getString("request_id").equals(c.opt("request_id"))||!"rejected".equals(c.opt("phase"))||!"rejected".equals(c.opt("outcome")))return false;
        JSONArray requested=body.optJSONArray("ranges"),rows=c.optJSONArray("range_outcomes");
        if(requested==null||rows==null||requested.length()<1||requested.length()>2||requested.length()!=rows.length())return false;
        HashSet<String> ids=new HashSet<>();
        for(int i=0;i<requested.length();i++){
            JSONObject r=requested.optJSONObject(i);if(r==null||!(r.opt("id") instanceof String))return false;
            String id=r.getString("id");if((!id.equals("1")&&!id.equals("2"))||!ids.add(id))return false;
        }
        for(int i=0;i<rows.length();i++){
            JSONObject r=rows.optJSONObject(i);if(r==null||!(r.opt("range_id") instanceof String)||!ids.remove(r.getString("range_id")))return false;
            if(!"rejected".equals(r.opt("status"))&&!"not_dispatched".equals(r.opt("status")))return false;
        }
        return ids.isEmpty();
    }
    static boolean partialMatchesRequest(JSONObject command,JSONObject body)throws JSONException {
        if(partialMessage(command)==null)return false;
        JSONArray requested=body.optJSONArray("ranges"),outcomes=command.optJSONArray("range_outcomes");
        if(requested==null||requested.length()!=outcomes.length())return false;
        HashSet<String> ids=new HashSet<>();
        for(int i=0;i<requested.length();i++){JSONObject r=requested.optJSONObject(i);if(r==null||!(r.opt("id") instanceof String)||!ids.add(r.getString("id")))return false;}
        for(int i=0;i<outcomes.length();i++)if(!ids.remove(outcomes.getJSONObject(i).getString("range_id")))return false;
        return ids.isEmpty();
    }
    static String partialMessage(JSONObject command)throws JSONException {
        JSONArray rows=command.optJSONArray("range_outcomes");
        if(rows==null||rows.length()<1||rows.length()>2)return null;
        HashSet<String> ids=new HashSet<>();StringBuilder text=new StringBuilder("Применено частично.\n");
        boolean incomplete=false,applied=false;
        for(int i=0;i<rows.length();i++){
            JSONObject row=rows.optJSONObject(i);if(row==null)return null;
            Object rawId=row.opt("range_id");if(!(rawId instanceof String))return null;
            String id=(String)rawId;if((!id.equals("1")&&!id.equals("2"))||!ids.add(id))return null;
            Object status=row.opt("status");String label;
            if("confirmed".equals(status)){label="первичная отправка подтверждена";applied=true;}
            else if("not_dispatched".equals(status)){label="не отправлен";incomplete=true;}
            else if("rejected".equals(status)){label="отклонён";incomplete=true;}
            else return null;
            text.append("Диапазон №").append(id).append(": ").append(label).append(".\n");
        }
        return incomplete&&applied?text.append("Автоматического повтора нет. Текущее состояние позиций и триггеров показано ниже.").toString():null;
    }
}
