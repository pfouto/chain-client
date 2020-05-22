import channel.ChannelEvent;
import channel.ChannelListener;
import channel.simpleclientserver.SimpleClientChannel;
import channel.simpleclientserver.events.ServerDownEvent;
import channel.simpleclientserver.events.ServerFailedEvent;
import channel.simpleclientserver.events.ServerUpEvent;
import io.netty.channel.EventLoopGroup;
import network.*;
import network.data.Host;
import site.ycsb.ByteIterator;
import site.ycsb.DB;
import site.ycsb.Status;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

public class ChainClient extends DB implements ChannelListener<ProtoMessage> {

  private static AtomicInteger idCounter;
  private static final AtomicInteger initCounter = new AtomicInteger();

  private static int timeoutMillis;

  private static final Map<Host, CompletableFuture<Void>> connectFutures = new ConcurrentHashMap<>();

  private static Map<Host, SimpleClientChannel<ProtoMessage>> servers;
  private static final ThreadLocal<Map.Entry<Host, SimpleClientChannel<ProtoMessage>>> threadServer = new ThreadLocal<>();
  private static final Map<Integer, CompletableFuture<ResponseMessage>> callbacks = new ConcurrentHashMap<>();

  @Override
  public void init() {
    try {
      //System.err.println(i1 + " " + Thread.currentThread().toString());
      synchronized (callbacks) {
        if (servers == null) {
          //ONCE
          timeoutMillis = Integer.parseInt(getProperties().getProperty("timeout_millis"));
          int serverPort = Integer.parseInt(getProperties().getProperty("frontend_server_port"));
          int myNumber = Integer.parseInt(getProperties().getProperty("node_number"));
          idCounter = new AtomicInteger(myNumber * 10000000);
          //System.err.println("My id: " + myNumber + " field length: " + getProperties().getProperty("fieldlength") +
          //    " client id: " + idCounter.get());

          EventLoopGroup workerGroup = NetworkManager.createNewWorkerGroup();
          servers = new HashMap<>();
          BaseProtoMessageSerializer serializer = new BaseProtoMessageSerializer(new ConcurrentHashMap<>());
          serializer.registerProtoSerializer(RequestMessage.MSG_CODE, RequestMessage.serializer);
          serializer.registerProtoSerializer(ResponseMessage.MSG_CODE, ResponseMessage.serializer);

          String host = getProperties().getProperty("hosts");
          String[] hosts = host.split(",");

          for (String s : hosts) {
            Host h = new Host(InetAddress.getByName(s), serverPort);
            connectFutures.put(h, new CompletableFuture<>());
            Properties p = new Properties();
            p.setProperty(SimpleClientChannel.ADDRESS_KEY, h.getAddress().getHostAddress());
            p.setProperty(SimpleClientChannel.PORT_KEY, String.valueOf(h.getPort()));
            p.put(SimpleClientChannel.WORKER_GROUP_KEY, workerGroup);
            servers.put(h, new SimpleClientChannel<>(serializer, this, p));
          }
          for (CompletableFuture<Void> f : connectFutures.values()) {
            f.get();
          }
          //System.err.println("Connected to all servers!");
          //END ONCE ----------
        }
        int threadId = initCounter.incrementAndGet();
        int randIdx = threadId % servers.size();
        Map.Entry<Host, SimpleClientChannel<ProtoMessage>> value = null;
        Iterator<Map.Entry<Host, SimpleClientChannel<ProtoMessage>>> iterator = servers.entrySet().iterator();
        for (int i = 0; i < randIdx+1; i++)
          value = iterator.next();
        if (value == null) throw new AssertionError();
        threadServer.set(value);
      }
    } catch (UnknownHostException | InterruptedException | ExecutionException e) {
      e.printStackTrace();
      System.exit(1);
    }
  }

  @Override
  public Status read(String table, String key, Set<String> fields, Map<String, ByteIterator> result) {
    try {
      //System.err.println("Read: " + key);
      int id = idCounter.incrementAndGet();
      RequestMessage requestMessage = new RequestMessage(id, RequestMessage.READ, key.getBytes());
      return executeOperation(requestMessage);
    } catch (Exception e) {
      e.printStackTrace();
      System.exit(1);
      return Status.ERROR;
    }
  }

  @Override
  public Status insert(String table, String key, Map<String, ByteIterator> values) {
    try {
      byte[] value = values.entrySet().iterator().next().getValue().toArray();
      //System.err.println("Insert: " + key + " : " + value);
      int id = idCounter.incrementAndGet();
      //System.err.println(id);
      RequestMessage requestMessage = new RequestMessage(id, RequestMessage.WRITE, value);
      return executeOperation(requestMessage);
    } catch (Exception e) {
      e.printStackTrace();
      System.exit(1);
      return Status.ERROR;
    }
  }

  private Status executeOperation(RequestMessage requestMessage) throws InterruptedException, ExecutionException {
    //System.err.println(requestMessage);
    CompletableFuture<ResponseMessage> future = new CompletableFuture<>();
    callbacks.put(requestMessage.getOpId(), future);
    Map.Entry<Host, SimpleClientChannel<ProtoMessage>> connection = threadServer.get();
    connection.getValue().sendMessage(requestMessage, null, -1);
    try {
      future.get(timeoutMillis, TimeUnit.MILLISECONDS);
      return Status.OK;
    } catch (TimeoutException ex) {
      System.err.println("Op Timed out..." + connection.getKey() + " " + requestMessage.getOpId());
      System.exit(1);
      return Status.SERVICE_UNAVAILABLE;
    }
  }

  @Override
  public Status scan(String t, String sK, int rC, Set<String> f, Vector<HashMap<String, ByteIterator>> res) {
    throw new AssertionError();
  }

  @Override
  public Status update(String table, String key, Map<String, ByteIterator> values) {
    throw new AssertionError();
  }

  @Override
  public Status delete(String table, String key) {
    throw new AssertionError();
  }

  @Override
  public void deliverMessage(ProtoMessage msg, Host from) {
    try {
      ResponseMessage resp = (ResponseMessage) msg;
      //System.err.println(msg);
      callbacks.get(resp.getOpId()).complete(resp);
    } catch (Exception e) {
      System.err.println(e.getMessage());
    }
  }

  @Override
  public void messageSent(ProtoMessage msg, Host to) {

  }

  @Override
  public void messageFailed(ProtoMessage msg, Host to, Throwable cause) {
    System.err.println("Message Failed: " + msg);
  }

  @Override
  public void deliverEvent(ChannelEvent evt) {
    if (evt instanceof ServerUpEvent) {
      connectFutures.get(((ServerUpEvent) evt).getServer()).complete(null);
    } else if (evt instanceof ServerDownEvent) {
      throw new AssertionError("Server connection lost: " + evt);
    } else if (evt instanceof ServerFailedEvent) {
      throw new AssertionError("Server connection failed: " + evt);
    } else {
      throw new AssertionError("Unexpected event: " + evt);
    }
  }
}
