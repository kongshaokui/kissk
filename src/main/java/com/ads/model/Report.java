package com.ads.model;

import java.util.Date;

public class Report {
    private Integer id;

    private Date createdate;

    private String channel;

    private String request;

    private String fill;

    private String impression;

    private String click;

    private String ctr;

    private String rev;

    private String ecpm;

    public Integer getId() {
        return id;
    }

    public void setId(Integer id) {
        this.id = id;
    }

    public Date getCreatedate() {
        return createdate;
    }

    public void setCreatedate(Date createdate) {
        this.createdate = createdate;
    }

    public String getChannel() {
        return channel;
    }

    public void setChannel(String channel) {
        this.channel = channel == null ? null : channel.trim();
    }

    public String getRequest() {
        return request;
    }

    public void setRequest(String request) {
        this.request = request == null ? null : request.trim();
    }

    public String getFill() {
        return fill;
    }

    public void setFill(String fill) {
        this.fill = fill == null ? null : fill.trim();
    }

    public String getImpression() {
        return impression;
    }

    public void setImpression(String impression) {
        this.impression = impression == null ? null : impression.trim();
    }

    public String getClick() {
        return click;
    }

    public void setClick(String click) {
        this.click = click == null ? null : click.trim();
    }

    public String getCtr() {
        return ctr;
    }

    public void setCtr(String ctr) {
        this.ctr = ctr == null ? null : ctr.trim();
    }

    public String getRev() {
        return rev;
    }

    public void setRev(String rev) {
        this.rev = rev == null ? null : rev.trim();
    }

    public String getEcpm() {
        return ecpm;
    }

    public void setEcpm(String ecpm) {
        this.ecpm = ecpm == null ? null : ecpm.trim();
    }
}