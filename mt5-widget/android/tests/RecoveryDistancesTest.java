package com.mihail.mt5panel;
public class RecoveryDistancesTest {
    static int n;
    static void check(boolean b){n++;if(!b)throw new AssertionError("check "+n);}
    public static void main(String[] args){
        RecoveryDistances d=new RecoveryDistances("0.70","1.20");check(d.initialSl.equals("0.7"));check(d.supportReentry.equals("1.2"));
        d=new RecoveryDistances("1.50","0,40");check(d.initialSl.equals("1.5"));check(d.supportReentry.equals("0.4"));
        d=new RecoveryDistances(RecoveryDistances.DEFAULT,RecoveryDistances.DEFAULT);check(d.initialSl.equals("0.7")&&d.supportReentry.equals("0.7"));
        check(RecoveryDistances.positive(" 0.01 ").equals("0.01"));
        for(String bad:new String[]{null,"","0","0.00","-1","NaN","Infinity","1e5","1e999999","1,2,3","1.123456789","1234567890123"}){try{new RecoveryDistances(bad,"0.7");throw new AssertionError("Accepted invalid SL");}catch(IllegalArgumentException ok){n++;}try{new RecoveryDistances("0.7",bad);throw new AssertionError("Accepted invalid reentry");}catch(IllegalArgumentException ok){n++;}}
        System.out.println("RecoveryDistancesTest passed: "+n);
    }
}
