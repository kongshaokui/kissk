package com.ads.study.Event;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-09-14
 * Time: 16:08
 */
public class Door {

    private static DoorListener doorListener;

    public void openDoor(){
        System.out.println("门开了");
        DoorEvent doorEvent = new DoorEvent(this, "开");
        notifyListener(doorEvent);
    }

    public void closeDoor(){
        System.out.println("门关了");
        DoorEvent doorEvent = new DoorEvent(this, "关");
        notifyListener(doorEvent);
    }

    /**
     * 注册监听器
     * @param listener
     */
    public void register(DoorListener listener){
        this.doorListener=listener;
    }

    public static void notifyListener(DoorEvent doorEvent){
        doorListener.doorEvent(doorEvent);
    }


}
