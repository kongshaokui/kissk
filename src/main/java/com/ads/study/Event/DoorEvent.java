package com.ads.study.Event;

import java.util.EventObject;

/**
 * 事件状态对象
 * User: kismetkong@tcl.com
 * Date: 2018-09-14
 * Time: 15:49
 */
public class DoorEvent extends EventObject {

    private String state="";

    /**
     * Constructs a prototypical Event.
     *
     * @param source The object on which the Event initially occurred.
     * @throws IllegalArgumentException if source is null.
     */
    public DoorEvent(Object source,String state) {
        super(source);
        setState(state);
    }

    public String getState() {
        return state;
    }

    public void setState(String state) {
        this.state = state;
    }
}
