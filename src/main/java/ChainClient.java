import io.netty.bootstrap.Bootstrap;
import io.netty.channel.*;
import io.netty.channel.nio.NioEventLoopGroup;
import io.netty.channel.socket.SocketChannel;
import io.netty.channel.socket.nio.NioSocketChannel;
import network.RequestEncoder;
import network.RequestMessage;
import network.ResponseDecoder;
import network.ResponseMessage;
import site.ycsb.ByteIterator;
import site.ycsb.DB;
import site.ycsb.Status;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

public class ChainClient extends DB {

  private static final AtomicInteger initCounter = new AtomicInteger();
  private static final ThreadLocal<Channel> threadServer = new ThreadLocal<>();
  private static final Map<Channel, Map<Integer, CompletableFuture<ResponseMessage>>> opCallbacks = new HashMap<>();
  private static AtomicInteger idCounter;
  private static int timeoutMillis;
  private static byte readType;
  private static List<Channel> servers;
  private static String[] weights;
  private static double totalWeight;

  @Override
  public void init() {
    try {
      //System.err.println(i1 + " " + Thread.currentThread().toString());
      synchronized (opCallbacks) {
        if (servers == null) {
          //ONCE
          timeoutMillis = Integer.parseInt(getProperties().getProperty("timeout_millis"));
          int serverPort = Integer.parseInt(getProperties().getProperty("app_server_port"));
          int nFrontends = Integer.parseInt(getProperties().getProperty("n_frontends"));
          String readProp = getProperties().getProperty("read_type", "strong");
          if (readProp.equals("weak")) readType = RequestMessage.WEAK_READ;
          else if (readProp.equals("strong")) readType = RequestMessage.STRONG_READ;
          idCounter = new AtomicInteger(0);
          //System.err.println("My id: " + myNumber + " field length: " + getProperties().getProperty("fieldlength") +
          //    " client id: " + idCounter.get());

          servers = new LinkedList<>();

          String host = getProperties().getProperty("hosts");
          String[] hosts = host.split(",");

          totalWeight = 0;
          if (getProperties().containsKey("weights") && !getProperties().getProperty("weights").isEmpty()) {
            weights = getProperties().getProperty("weights").split(":");

            if (weights.length != hosts.length * nFrontends) {
              System.err.println("Weight does not match hosts");
              System.exit(-1);
            }

            for (String weight : weights) totalWeight += Double.parseDouble(weight);
          }

          EventLoopGroup workerGroup = new NioEventLoopGroup();
          Bootstrap b = new Bootstrap();
          b.group(workerGroup);
          b.channel(NioSocketChannel.class);
          b.option(ChannelOption.SO_KEEPALIVE, true);
          b.handler(new ChannelInitializer<SocketChannel>() {
            @Override
            public void initChannel(SocketChannel ch) {
              //System.err.println("InitChannel: " + ch);
              ch.pipeline().addLast(new RequestEncoder(), new ResponseDecoder(), new ClientHandler());
            }
          });

          List<ChannelFuture> connectFutures = new LinkedList<>();
          for (String s : hosts) {
            for (int f = 0; f < nFrontends; f++) {
              InetAddress addr = InetAddress.getByName(s);
              int port = serverPort + f;
              //System.err.println("Connecting to " + addr + ":" + port);
              ChannelFuture connect = b.connect(addr, port);
              connectFutures.add(connect);
              servers.add(connect.channel());
              opCallbacks.put(connect.channel(), new ConcurrentHashMap<>());
            }
          }
          for (ChannelFuture f : connectFutures) {
            f.sync();
          }
          System.err.println("Connected to all servers!");
          //END ONCE ----------
        }
        int randIdx = -1;
        if (totalWeight == 0) {
          int threadId = initCounter.getAndIncrement();
          randIdx = threadId % servers.size();
        } else {
          double random = Math.random() * totalWeight;
          for (int i = 0; i < servers.size(); ++i) {
            random -= Double.parseDouble(weights[i]);
            if (random <= 0.0d) {
              randIdx = i;
              break;
            }
          }
        }

        threadServer.set(servers.get(randIdx));

      }
    } catch (UnknownHostException | InterruptedException e) {
      e.printStackTrace();
      System.exit(1);
    }
  }

  @Override
  public Status read(String table, String key, Set<String> fields, Map<String, ByteIterator> result) {
    try {
      int id = idCounter.incrementAndGet();
      RequestMessage requestMessage = new RequestMessage(id, readType, key, new byte[0]);
      return executeOperation(requestMessage);
    } catch (Exception e) {
      e.printStackTrace();
      System.exit(1);
      return Status.ERROR;
    }
  }

  @Override
  public Status update(String table, String key, Map<String, ByteIterator> values) {
    return insert(table, key, values);
  }

  @Override
  public Status insert(String table, String key, Map<String, ByteIterator> values) {
    try {
      byte[] value = values.values().iterator().next().toArray();
      int id = idCounter.incrementAndGet();
      RequestMessage requestMessage = new RequestMessage(id, RequestMessage.WRITE, key, value);
      return executeOperation(requestMessage);
    } catch (Exception e) {
      e.printStackTrace();
      System.exit(1);
      return Status.ERROR;
    }
  }

  private Status executeOperation(RequestMessage requestMessage) throws InterruptedException, ExecutionException {
    CompletableFuture<ResponseMessage> future = new CompletableFuture<>();
    Channel channel = threadServer.get();
    opCallbacks.get(channel).put(requestMessage.getcId(), future);
    channel.writeAndFlush(requestMessage);
    try {
      future.get(timeoutMillis, TimeUnit.MILLISECONDS);
      return Status.OK;
    } catch (TimeoutException ex) {
      System.err.println("Op Timed out..." + channel.remoteAddress() + " " + requestMessage.getcId());
      System.exit(1);
      return Status.SERVICE_UNAVAILABLE;
    }
  }

  @Override
  public Status scan(String t, String sK, int rC, Set<String> f, Vector<HashMap<String, ByteIterator>> res) {
    throw new AssertionError();
  }

  @Override
  public Status delete(String table, String key) {
    throw new AssertionError();
  }

  static class ClientHandler extends ChannelInboundHandlerAdapter {

    @Override
    public void userEventTriggered(ChannelHandlerContext ctx, Object evt) {
      System.err.println("Unexpected event, exiting: " + evt);
      System.exit(1);
      ctx.fireUserEventTriggered(evt);
    }

    @Override
    public void channelInactive(ChannelHandlerContext ctx) {
      System.err.println("Server connection lost, exiting: " + ctx.channel().remoteAddress());
      //System.exit(1);
      ctx.fireChannelInactive();
    }

    @Override
    public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
      System.err.println("Exception caught, exiting: " + cause);
      cause.printStackTrace();
      System.exit(1);
      ctx.fireExceptionCaught(cause);
    }

    @Override
    public void channelActive(ChannelHandlerContext ctx) {
      //System.err.println("Connected to " + ctx.channel());
    }

    @Override
    public void channelRead(ChannelHandlerContext ctx, Object msg) {
      //System.err.println("Message received: " + msg);
      ResponseMessage resp = (ResponseMessage) msg;
      opCallbacks.get(ctx.channel()).get(resp.getcId()).complete(resp);
    }
  }
}
