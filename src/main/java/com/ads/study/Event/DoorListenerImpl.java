package com.ads.study.Event;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-09-14
 * Time: 16:04
 */
public class DoorListenerImpl implements DoorListener{

    @Override
    public void doorEvent(DoorEvent doorEvent) {
        System.out.println(String.format("Listener is state %s",doorEvent.getState()));
    }
}
