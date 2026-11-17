package com.mihail.mt5panel;
public class ConfigTest {
 public static void main(String[] args) {
  if (!SecureConfig.validateUrl(" https://example.com/ ").equals("https://example.com")) throw new AssertionError();
  String[] invalid={"http://example.com","https://user:pass@example.com","https://example.com/path","https://example.com/?secret=1","https://example.com/#x","javascript:bad","", "https://"};
  for(String value:invalid){try{SecureConfig.validateUrl(value);throw new AssertionError(value);}catch(IllegalArgumentException expected){}}
  System.out.println("9 URL validation checks passed");
 }
}
