package com.mihail.mt5panel;
public class RecoveryDistancesTest {
    static int n;
    static void check(boolean b){n++;if(!b)throw new AssertionError("check "+n);}
    public static void main(String[] args){
        RecoveryDistances d=new RecoveryDistances("0.70","1.20");check(d.initialSl.equals("0.7"));check(d.supportReentry.equals("1.2"));
        d=new RecoveryDistances("1.50","0,40");check(d.initialSl.equals("1.5"));check(d.supportReentry.equals("0.4"));
        d=new RecoveryDistances(RecoveryDistances.DEFAULT,RecoveryDistances.DEFAULT);check(d.initialSl.equals("0.7")&&d.supportReentry.equals("0.7"));
        check(RecoveryDistances.positive(" 0.01 ").equals("0.01"));
        for(String allowed:new String[]{"0.60","0,60"," 0.60000000 ","0.60000001"}){
            d=new RecoveryDistances(allowed,"0.01");check(new java.math.BigDecimal(d.initialSl).compareTo(new java.math.BigDecimal("0.60"))>=0);check(d.supportReentry.equals("0.01"));
        }
        for(String below:new String[]{"0.01","0.25","0.59","0.59999999"}){
            try{new RecoveryDistances(below,"0.7");throw new AssertionError("Accepted SL below minimum");}catch(IllegalArgumentException ok){check(ok.getMessage().contains("0,60"));}
        }
        for(String bad:new String[]{null,"","0","0.00","-1","NaN","Infinity","1e5","1e999999","1,2,3","1.123456789","1234567890123"}){try{new RecoveryDistances(bad,"0.7");throw new AssertionError("Accepted invalid SL");}catch(IllegalArgumentException ok){n++;}try{new RecoveryDistances("0.7",bad);throw new AssertionError("Accepted invalid reentry");}catch(IllegalArgumentException ok){n++;}}
        System.out.println("RecoveryDistancesTest passed: "+n);
    }
}
