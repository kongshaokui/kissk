package com.ads.model;

/**
 * @Title: EBaiCommon
 * @Desription: (描述此类的功能)
 * @author: lijuan.li
 * @date: 2018/9/18 下午6:13
 */
public class EBaiCommon<T> {
    private String cmd;
    private String sign;
    private String source;
    private String ticket;
    private Long timestamp;
    private int version;
    private String encrypt;
    private T body;

    public String getCmd() {
        return cmd;
    }

    public void setCmd(final String cmd) {
        this.cmd = cmd;
    }

    public String getSign() {
        return sign;
    }

    public void setSign(final String sign) {
        this.sign = sign;
    }

    public String getSource() {
        return source;
    }

    public void setSource(final String source) {
        this.source = source;
    }

    public String getTicket() {
        return ticket;
    }

    public void setTicket(final String ticket) {
        this.ticket = ticket;
    }

    public Long getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(final Long timestamp) {
        this.timestamp = timestamp;
    }

    public String getEncrypt() {
        return encrypt;
    }

    public void setEncrypt(final String encrypt) {
        this.encrypt = encrypt;
    }

    public int getVersion() {
        return version;
    }

    public void setVersion(final int version) {
        this.version = version;
    }

    public T getBody() {
        return body;
    }

    public void setBody(final T body) {
        this.body = body;
    }

    @Override
    public String toString() {
        return "EBaiCommon{" + "cmd='" + cmd + '\'' + ", sign='" + sign + '\'' + ", source='" + source + '\'' + ", ticket='" + ticket + '\'' + ", timestamp=" + timestamp + ", version=" + version + ", encrypt='" + encrypt + '\'' + ", body=" + body + '}';
    }
}
