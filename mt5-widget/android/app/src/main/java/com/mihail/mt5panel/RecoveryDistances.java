package com.mihail.mt5panel;

import java.math.BigDecimal;

/** Two independent price distances. No unit conversion or coupling. */
final class RecoveryDistances {
    static final String DEFAULT="0.70";
    final String initialSl, supportReentry;
    RecoveryDistances(String initialSl,String supportReentry){
        this.initialSl=positive(initialSl);this.supportReentry=positive(supportReentry);
    }
    static String positive(String text){
        if(text==null)throw new IllegalArgumentException("Missing distance");
        String normalized=text.trim().replace(',','.');
        // Accept ordinary decimal input only, avoiding exponent abuse and enormous values.
        if(!normalized.matches("[0-9]{1,12}(\\.[0-9]{1,8})?"))throw new IllegalArgumentException("Invalid distance");
        BigDecimal n=new BigDecimal(normalized);
        if(n.signum()<=0)throw new IllegalArgumentException("Distance must be positive");
        return n.stripTrailingZeros().toPlainString();
    }
}
